# 11 — System driver

## 1. Scope

`driver-system` — host facts, OS/package versions, live loads, network, running processes, and log
reads, exposed through the same driver-kit contract every other driver uses (05a). Its transport is
the filesystem and `/proc`, not a bus — 01 §2 already treats system configuration as a driver for
exactly this reason, the same way 06 treats a KV store as one.

**No write surface exists here in v1.** No `channel`, no `SET`, no mutating `method` — everything
below is `reading` or a `CALL` with `effect: 'none'`. This driver can see more of the host than any
other; §8 states why that stays one-directional for now.

## 2. Endpoints

| Tail | Shape | Cadence | Notes |
|---|---|---|---|
| `info` | reading | once, at `configure`/`reload` | host + hardware identity, OS/package versions — §3 |
| `load` | reading | scan loop | CPU, RAM, storage usage and mount layout together — §4 |
| `network` | reading | scan loop | interfaces and addresses — §5 |
| `processes` | method | on call | live process snapshot — §6 |
| `log` | method | on call | additive read from a configured journal or file source — §7 |

Five single-`'@'`-field devices (05a §3.3), all bound once at `attach()` (05a §3.8) — the same shape
06 §4 uses for the KV-store driver. The endpoint table never changes after startup: no dynamic
binding, no `generation` bump past the first one.

## 3. Host and identity facts — `info`

```ts
const SystemInfo = Codecs.struct({
  hostname:        Codecs.string(),
  machineId:        Codecs.string(),                 // /etc/machine-id, verbatim
  evokNodeVersion:  Codecs.string(),                  // this package's own package.json version
  osVersion:        Codecs.string(),                  // /etc/os-release, PRETTY_NAME
  packages:         Codecs.array(Codecs.struct({ name: Codecs.string(), version: Codecs.string() })),  // unipi-* entries, dpkg status db
  hardware:         Codecs.struct({ model: Codecs.string(), family: Codecs.string(), serialNumber: Codecs.string() }),  // §3.1 — absent when unresolved
});
const Info = device('info', { '@': reading('info', SystemInfo, { subscribe: false }) });
```

Computed once at `configure()`, recomputed at `reload()` only if config actually changed — never
re-read mid-run, because none of this changes without a restart. `/var/lib/dpkg/status` is parsed
directly for `unipi-*` entries; never `dpkg -l` (§8).

### 3.1. Hardware identity is borrowed, not detected here

`model`/`family`/`serialNumber` are 08's job (register 1004 and its census fallback) — this driver
never talks to Modbus. They appear only when this driver's own config names a `hardwareDriver` id,
reached through a declared link (01 §7, 02 §4) with one `CALL` against whatever 08 exposes for this.
No configured link, or a link with nothing to report ⇒ `hardware` is absent — 05 §2's "no value yet"
rule, never a guessed default. **Open** — the exact endpoint this calls on `driver-onboard` is 08's to
define; this file only commits to the shape of asking.

## 4. Loads — `load`

```ts
const SystemLoad = Codecs.struct({
  cpu:     Codecs.struct({ load1: Codecs.float32(), load5: Codecs.float32(), load15: Codecs.float32() }),   // /proc/loadavg
  ram:     Codecs.struct({ totalKb: Codecs.uint32(), usedKb: Codecs.uint32(), freeKb: Codecs.uint32() }),   // /proc/meminfo
  storage: Codecs.array(Codecs.struct({
    mount: Codecs.string(), device: Codecs.string(), fsType: Codecs.string(),
    totalKb: Codecs.uint32(), usedKb: Codecs.uint32(), freeKb: Codecs.uint32(),
  })),   // one entry per mounted filesystem in /proc/mounts — layout and usage travel together, never two endpoints
});
```

`subscribe: true`, refreshed by an ordinary `scheduleRepeating` scan (04 §5.2), `overrunPolicy:
'skip'` — a late CPU/RAM read next tick is harmless, the same reasoning 05 §4 gives for any read-only
scan. There is no separate "filesystem layout" endpoint: a mount's device/type and its usage numbers
are one array entry, and a mount that disappears between scans simply drops out of the array on the
next one, same as any other topology-shaped reading.

## 5. Network — `network`

```ts
const SystemNetwork = Codecs.struct({
  interfaces: Codecs.array(Codecs.struct({
    name: Codecs.string(), mac: Codecs.string(), up: Codecs.bool(),
    addresses: Codecs.array(Codecs.struct({ family: Codecs.string(), address: Codecs.string(), prefix: Codecs.uint8() })),
  })),
});
```

`subscribe: true`, same scan-loop treatment as `load`. **Open** — routes, DNS resolvers, and whether
an interface flap should push faster than the scan interval (netlink-driven rather than polling
`/proc/net`) are post-1.0 questions; v1 is poll-only.

## 6. Processes — `processes`

| Method | Effect | Args | Result | Notes |
|---|---|---|---|---|
| `processes` | `none` | *(none)* | `Process[]` | a snapshot, never a subscription |

```ts
type Process = { pid: number; name: string; cpuPct: number; rssKb: number };
```

Read straight from `/proc/<pid>/stat` and `/proc/<pid>/status` for every numeric entry under `/proc`
— never `ps`, never any exec (§8). Deliberately minimal: no cmdline, no uid, no thread count. A
client wanting more is asking for a different tool, not a bigger version of this one — the same
framing 06 §3 gives `get`/`has`.

## 7. Logs — `log`

| Method | Effect | Args | Result | Notes |
|---|---|---|---|---|
| `log` | `none` | `{ source: string, since?: LogCursor }` | `{ lines: LogLine[], cursor: LogCursor }` | `errorKinds: ['source-not-found', 'cursor-invalid']` |

```ts
type LogCursor = string;   // opaque per source — a journald cursor, or "<inode>:<byteOffset>" for a file
type LogLine   = { time: Date; text: string };
```

Additive by construction: call once with no `since`, get back `{lines, cursor}`; every following call
passes that `cursor` to get only what's new. `since` omitted means "from the start of what we still
retain," never "from the beginning of time" for a journal that outlives its own retention.
`cursor-invalid` — never a silently empty read — covers a file source that rotated out from under an
old offset; it's the client's own signal to restart from an empty `since`.

### 7.1. Sources are configured, never named freely

```yaml
drivers:
  SYS:
    type: system
    log:
      sources:
        - id: daemon
          kind: journal
          unit: evok-node.service        # journalctl --unit=..., --after-cursor for `since`
        - id: unipitcp
          kind: file
          path: /var/log/unipitcp.log    # cursor is "<inode>:<offset>"
```

A caller names a `source` id declared here; there is no path or unit a `CALL` can supply itself. This
is the direct fix for the `modbus_slave.set(print_log=N)` shell-out research/01 §3 flags — no
endpoint on this driver ever takes a filesystem path from a client.

## 8. Permissions — the security surface

This driver reads more of the host than any other, and calls no hardware at all, so its whole risk is
host-level, not bus-level:

- **No exec.** Every fact above comes from a file this driver parses itself (`/proc`, `/etc/os-release`,
  `/etc/machine-id`, `/var/lib/dpkg/status`) or a configured log source — never a spawned child
  process. `basics/02-Coding.md` §5's "prefer a maintained library" applies to the parsing, not to
  reaching for a shell instead of writing the parser.
- **No arbitrary file access.** Log sources are a closed, admin-configured allowlist (§7.1); nothing
  else on this driver accepts a path, a unit name, or a PID filter from a caller.
- **Read-only.** No `channel`, no `SET`, no mutating `method` exists here in v1 (§1). Anything beyond
  the five reads above answers `unknown-address` (03 §7), same as any other endpoint that doesn't
  exist.

Any future write — restart the daemon, reboot the host — is a new `method`, `effect: 'mutates'`,
reviewed on its own terms against this section; it is not implied by anything already here.

## 9. Placement

`worker_thread` (default). Nothing here is native code or CPU-heavy — a handful of `/proc` reads and
a config-sized set of log sources — so 01 §8's `child_process` case for native-crash isolation doesn't
apply, the same reasoning 06 §9 gives for the KV-store driver.

## 10. Testing

Tier 1 (unit; `basics/03-Testing.md`) only — no simulator, no hardware rig, this driver never touches
a bus:

- `info`/`load`/`network` parse fixed-format fixtures (a captured `/proc/meminfo`, `/etc/os-release`,
  a dpkg status db) into the exact struct shapes above; a malformed fixture is a parse failure, never
  a crash.
- `processes` against a fixture `/proc`-shaped directory tree — never the real one.
- `log`: additive read-then-resume against a fixture journal export and a fixture file, including the
  rotated-file case answering `cursor-invalid`; a `source` not in config answers `source-not-found`.
- Permissions: assert no test double for `child_process.exec`/`spawn` is ever invoked by this
  package — a standing guard, not a one-off assertion.

## 11. Open

- Hardware identity link to `driver-onboard` (§3.1) — the concrete endpoint depends on 08.
- Network: routes, DNS, event-driven refresh versus poll-only (§5).
- Whether a user-settable `label` belongs on `info` at all, and if so where it's stored (the KV-store
  driver, 06) and what write path exposes it — no driver has a write surface yet, so this is genuinely
  undecided, not merely deferred.
- Whether the compat surface (14) needs anything from this driver — `device_info`, `/version` — before
  post-1.0, per research/01 §2 and §9.
