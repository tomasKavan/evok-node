# 04 — Common services

## 1. Scope

The shared runtime a module may lean on that is not messaging (03), config (02) or the KV-store driver (06): **logging, time, scheduling, and deadlines/cancellation.**

Error handling is decided elsewhere. The general shape — expected failure is a value, `throw` is for broken invariants, error kinds are string-literal unions — is `basics/02-Coding.md` §2. The one piece still open, how an error crosses the driver↔api envelope itself, is 03's, because it cannot be settled without the envelope shape it lives in.

## 2. Where this lives

`@evok-node/module-sdk` (01 §11) is where `Logger`, `Clock`, `Deadline` and the scheduler helper are typed and published — `InstanceContext` already lives there (02 §4), and a third-party plugin author needs these exactly as much as a built-in driver does. The actual sinks a `Logger` writes to — the pino instance(s), the file/stdout destinations — are constructed once, in `main`, because `main` is the only thing ever allowed to touch them (§3.2). A plugin author imports the interface, never a concrete pino handle.

## 3. Logging

### 3.1. Framework: pino

Structured JSON by default, fast, `logger.child({...})` for scoping, and — per `basics/02-Coding.md` §5.1 — a widely used, maintained library rather than something hand-rolled. Research/08 already establishes that Node is not the bottleneck on the scan path; the choice here is about the API side under load and about correlation-id propagation being free rather than reinvented, not about shaving microseconds off a driver's poll loop.

### 3.2. One writer, reached the same way regardless of placement

Every instance gets a scoped `Logger` through `InstanceContext`, the same object shape under either placement (01 §3):

```ts
// @evok-node/module-sdk
interface Logger {
  trace(msg: string, fields?: Record<string, unknown>): void;
  debug(msg: string, fields?: Record<string, unknown>): void;
  info(msg: string, fields?: Record<string, unknown>): void;
  warn(msg: string, fields?: Record<string, unknown>): void;
  error(msg: string, err?: unknown, fields?: Record<string, unknown>): void;
  fatal(msg: string, err?: unknown, fields?: Record<string, unknown>): void;
  child(fields: Record<string, unknown>): Logger;   // e.g. { correlationId } from an envelope (03)
}
```

Only `main` ever holds a real pino instance. Every instance runs in its own `worker_thread` or `child_process` (01 §3), so `ctx.log` is always crossing that boundary: a log call becomes a message over the same channel as everything else crossing it (03), fire-and-forget, never awaited, queued with a bounded size and a drop-oldest policy under backpressure. A log line must never be able to block a scan — 01 §8 ("nothing on the driver↔api boundary may block") applies here too, even though a log call isn't a request/response.

### 3.3. Sinks and configuration

Two sinks always exist, one is optional, and the door stays open for more:

- **stdout, always, as NDJSON.** Under systemd this lands in the journal with no special integration code — structured JSON survives as the message field, and a human reads it with `journalctl -u evok-node | pino-pretty` or `journalctl -o cat -u evok-node`. This is the sink that can never be turned off, because it is what makes a startup failure visible before anything else in this file's own configuration can be trusted (§3.3.1).
- **a file, if configured.** `logging.file` in `config.yaml` gives a path; rotation is `logrotate`'s job, not ours (`basics/02-Coding.md` §5.1 — prefer the existing tool).
- **a future collector, deliberately not built now.** pino's transport mechanism (a worker-thread destination, or any writable stream) is the seam: `main` constructs whatever set of destinations `logging` names via `pino.multistream`, and nothing else in the codebase knows a collector exists. Adding one later is a new destination and, if needed, one new optional config key — never a change to how a `Logger` is used.

```yaml
# /etc/evok-node/config.yaml
logging:
  level: info                              # trace..fatal (§3.6); default info
  file: /var/log/evok-node/evok-node.log   # optional — omit for stdout/journald only
  pretty: false                            # dev convenience only; never what's persisted (§3.4)

drivers:
  # ...
apis:
  # ...
```

This adds one optional key to 02 §3's `ConfigFile` schema, validated by `main` itself — same category as `drivers:`/`apis:`, because logging is main's own operational setting, not a module default leaking in. 02 §3 is amended accordingly.

#### 3.3.1. Bootstrap ordering

`logging.file` cannot be read from a config that has not parsed yet, and a parse failure is exactly the thing most worth logging (02 §5, steps 2–3). So logging starts, before 02 §5's step 1, at stdout-only, level `info` — the one sink that needs no configuration to exist. Once config parsing (02 §5 steps 2–4) succeeds, `main` reconfigures the same `Logger` in place to add the file destination and any non-default level. A config that never parses is therefore still fully logged; it just never gets the file sink.

### 3.4. Format: one canonical shape, any number of views

The canonical, persisted form is structured JSON, one object per line — what gets written to stdout, to the file, and to a collector later. Nothing downstream reformats it, so `jq`, `grep` and a log shipper all keep working against the same shape forever.

Human-readability is a presentation concern layered on top, never a second stored format: `pino-pretty` as a transport when `logging.pretty: true` (meant for a developer's own terminal, not for what a service unit or a collector receives), or piped in ad hoc over `journalctl -f`. There is exactly one thing on disk; there are as many ways to look at it as there are tools that read NDJSON.

### 3.5. Fields

| Field | Meaning |
|---|---|
| `time` | Wall-clock, for humans and for a collector's own timestamping. Never used for duration or staleness (§4.1) — that is what `Date.now()` outside logging is banned for (`basics/02-Coding.md` §4.2). |
| `level` | One of §3.6's six. |
| `instanceId` | The driver/api id from config (02 §3) — absent for a log line from `main` itself. |
| `placement` | `worker_thread` \| `child_process` (01 §3), so a reader can tell which runner a line came through without needing to already know the config. |
| `correlationId` | Present when the log call happened inside a request/response/event's scope (03) — a `child()` logger set it once, not threaded through every call site by hand. |
| `msg` | One line, imperative or descriptive, no interpolated values that belong in `fields` instead — that's what structured fields are for. |
| `err` | Present on `error`/`fatal` calls that carry one, via `pino.stdSerializers.err` — a real stack, not `String(err)`. |

### 3.6. Levels — one taxonomy, reused wherever severity needs a name

Pino's six standard levels are adopted as *the* severity vocabulary for this codebase, not only for log calls:

| Level | Means | Example |
|---|---|---|
| `trace` | Step-by-step detail, off by default, never in production | one Modbus transaction's raw bytes |
| `debug` | Detail useful while developing or diagnosing, off by default in production | a reload's prepare/commit barrier resolving |
| `info` | Normal operation worth a record | instance started, reload applied, config change accepted |
| `warn` | Degraded but not failed — 05's degradation levels report through here | a device unreachable, still retrying |
| `error` | A request or an operation failed; the instance survives | a write rejected, a parse failure on one message |
| `fatal` | The instance (or the daemon) cannot continue — 05's "fatal is reserved, enumerate exactly what qualifies" is the same reservation here | a duplicate endpoint address, a manifest collision (02 §4) |

The point of reusing pino's own six rather than inventing a parallel set: when 03 settles how a driver reports a health flip, or main escalates a fatal instance failure, the word it reaches for is already this file's word, not a second enum that happens to mean the same six things. `fatal` here and "fatal" in 05 name the same event, once.

## 4. Time

### 4.1. The Clock

`basics/02-Coding.md` §4.2 already bans `Date.now()` outside logging and requires an injected, monotonic source for anything measuring duration or staleness. This file names that source:

```ts
// @evok-node/module-sdk
interface Clock {
  now(): Millis;   // monotonic; never wall-clock, never affected by an NTP step
}
```

`SystemClock` wraps `process.hrtime.bigint()` and is what `InstanceContext` actually hands out. A `FakeClock` — settable, advanceable by a test — is the only other implementation that should ever exist; nothing else needs a second one. Every duration and every staleness check in the codebase reads this clock, never the wall clock.

One consequence worth stating plainly: `process.hrtime`'s reference point is chosen once, per process, and means nothing to any other process. Two instances always read *different* clocks now that every one runs in its own `worker_thread` or `child_process` (01 §3) — `now()` values, and anything built from one without going back through `remaining`/`deadlineFrom` first, are never comparable across that boundary. §6.2a is the consequence for `Deadline` specifically.

## 5. Scheduling

### 5.1. Why not raw `setInterval`

1. **No drift correction.** `setInterval(fn, 1000)` fires 1000 ms after the *previous callback returned*, not 1000 ms after the *previous scheduled time* — a scan that takes 50 ms to run drifts by 50 ms every cycle, compounding.
2. **No overlap protection.** If a callback ever takes longer than the interval, Node still queues the next tick — a slow bus response can pile up concurrent scans against a resource that 01 §7 already requires be arbitrated by exactly one owner, turning a slow response into lock contention instead of just a slow response.
3. **Not tied to any lifecycle.** A component that forgets `clearInterval` on `stop()` leaks a timer that outlives its instance — `basics/02-Coding.md` §4.1 requires every `setInterval` to have an abort path tied to a lifecycle, and a bare `setInterval` call has none by construction.

### 5.2. `scheduleRepeating`

```ts
// @evok-node/module-sdk
type OverrunPolicy =
  | 'skip'      // the run in flight is left to finish; the missed tick is simply not run
  | 'coalesce'; // the run in flight is left to finish; exactly one run follows immediately after,
                // folding any number of missed ticks into that one — never a queue of them

interface RepeatingTask {
  stop(): void;   // called from the runner's drain/stop (01 §4) — never left for the instance to remember on its own
}

function scheduleRepeating(
  clock: Clock,
  intervalMs: Millis,
  overrunPolicy: OverrunPolicy,
  task: (deadline: Deadline) => Promise<void>,
): RepeatingTask;
```

Ticks are scheduled against the *target* time — `start + n * intervalMs` — never against "whenever the last one finished," which is the drift correction §5.1 asks for. `overrunPolicy` is a choice the caller states explicitly every time, never a hidden default: `'skip'` fits a read-only scan where a stale reading next cycle is harmless; `'coalesce'` fits work that must eventually happen exactly once per real change, not once per missed tick. Which one a given scan loop should use is 05's/06's call to make, not this file's — this file only guarantees the primitive exists and that both choices are honest about what they do.

## 6. Deadlines and cancellation

### 6.1. A deadline is a value, not a duration

```ts
// @evok-node/module-sdk
type Deadline = Brand<Millis, 'Deadline'>;   // an absolute point on Clock's own scale, never "ms from now" — that rots the moment it sits in a queue before anyone reads it

function deadlineFrom(clock: Clock, budgetMs: Millis): Deadline;
function remaining(clock: Clock, deadline: Deadline): Millis;   // clamped to 0, never negative
function signalFor(clock: Clock, deadline: Deadline): AbortSignal;
```

This is the concrete form of what 01 §5 already requires — "the deadline is part of the envelope, not a per-call-site afterthought" — and it reuses `basics/02-Coding.md` §1.1's brand pattern rather than introducing a second convention for the same idea.

### 6.2. Propagation

When a call spawns another — an api's request reaching a driver, that driver's own call into a shared transport it doesn't own outright (01 §7) — the inner call's deadline is `min(remaining(clock, outerDeadline), innerCall'sOwnDefaultTimeout)`, never longer than what the caller has left. A shared transport with its own generous timeout must not be able to make a caller wait past a budget the caller already set.

### 6.2a. Crossing a link

§4.1 already says why: `Clock`'s scale is per-process, so a `Deadline` — an absolute point on *some* `Clock`'s scale — means nothing on another process's `Clock`. Every messaging link (03 §10) crosses exactly this boundary now that every instance runs in its own `worker_thread` or `child_process` (01 §3), so the sender's raw `Deadline` can never be what actually travels the wire.

What crosses instead is `remaining(senderClock, deadline)` — a plain duration, already clamped to 0, meaningful regardless of which process reads it — and the receiver reconstructs its own local `Deadline` via `deadlineFrom(receiverClock, thatDuration)` before building the `Request` its own module code ever sees. Nothing new to build: both functions already exist for exactly this; this is a rule about calling them at every hop, not a new primitive. It composes the same way §6.2's propagation rule does across an inner call — a driver forwarding to a transport driver it shares (01 §7) reconstructs again at that hop, using its own already-reconstructed `Deadline` as the outer bound.

### 6.3. Enforcement

Every wait races against the `AbortSignal` `signalFor` produces, derived from the injected `Clock` — never `AbortSignal.timeout()`, which reads the wall clock and inherits the same NTP-step problem §4.1 exists to avoid. This is the mechanism behind `basics/02-Coding.md` §4.1's "no unbounded loop, no promise without a timeout, no `setTimeout`/`setInterval` without an abort path tied to a lifecycle" — that rule states the requirement; this section states the one way it is satisfied, so there is a single pattern to review against rather than one per call site.
