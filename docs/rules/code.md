# Code rules

Binding. Cite as **RC-N**. Breaking one is a blocking review comment; the enforcement column says
what catches it, so you can check before pushing.

**If a rule can be a lint rule, it must be a lint rule.** Prose-only rules get ignored — by agents
and humans alike. What follows is prose only where a linter cannot express it.

| Tool | Catches |
|---|---|
| `tsc --strict` + `noUncheckedIndexedAccess`, `exactOptionalPropertyTypes`, `noImplicitOverride`, `noFallthroughCasesInSwitch` | type-level rules |
| `eslint` + `@typescript-eslint`, type-checked | RC-2, RC-14, RC-15, RC-16, RC-23 |
| `dependency-cruiser` | RC-10, RC-11, RC-30 (partly), import cycles, undeclared imports |
| `prettier` | formatting — never discussed in review |

`dependency-cruiser` is load-bearing. npm workspaces give every package a flat `node_modules`, so
without it nothing stops a driver importing an API — or `main` importing either, which is the edge
that would quietly put it back in the data path.

## Types

**RC-1 — Brand every number that means something.** Register addresses, coil addresses, unit ids
and bit offsets are all plain `number`, and EVOK's worst bug was writing a coil address where a
register address belonged.

```ts
type Brand<T, B> = T & { readonly __brand: B };
export type RegisterAddress = Brand<number, 'RegisterAddress'>;
export type CoilAddress     = Brand<number, 'CoilAddress'>;
export type UnitId          = Brand<number, 'UnitId'>;
export type BitOffset       = Brand<number, 'BitOffset'>;
export type Millis          = Brand<number, 'Millis'>;
export type DriverId        = Brand<string, 'DriverId'>;
export type Address         = Brand<string, 'Address'>;   // "PLC:DI.2.01" — ADR-0002
export type MessageId       = Brand<string, 'MessageId'>;
export type Seq             = Brand<number, 'Seq'>;
export type Circuit         = Brand<string, 'Circuit'>;   // EVOK's `2_01`. api-compat only
```

The constructor lives with the type and checks range (`unitId` 0–255, `bitOffset` 0–15). There is
no unchecked way to get a branded value.

**RC-2 — No `any`, no `as`, no `!`** outside generated code. Parse at the boundary (RC-12), and
after that the type is real.

**RC-3 — Discriminated unions, not optional fields.** A device is `{kind:'di', …} | {kind:'ao', …}`,
never one interface with everything optional. A `switch` with no `default`, in a function with a
declared return type, then makes a missing case a compile error. That is the bug class that left
EVOK's `ds_mode` permanently stuck.

**RC-4 — `readonly` by default, and hardware definitions are also frozen at load.** Upstream needed
a `copy()`→`deepcopy()` fix because two slaves shared one mutable array. Frozen *per load*, not once
per process — definitions reload when hardware changes (G-5).

**RC-5 — Decode returns a value on every path.** `decode(registers) => State`. Never mutate state in
place and fall through.

## Errors

**RC-6 — Expected failure is a value; a bug is a `throw`.** Expected failure returns
`{ok:true, …} | {ok:false, kind:…}`, and the compiler must make ignoring the failure arm impossible.
`throw` is for broken invariants only, and is never caught for control flow.

**RC-7 — A Modbus exception PDU is a failure.** Never a value a caller can mistake for success.

**RC-8 — No empty `catch {}` on an event or delivery path.** Log and count, with dedup.

**RC-9 — Error kinds are string-literal unions, not classes.** They cross the API boundary, so they
must serialise. At minimum: `bad_request`, `unknown_circuit`, `unsupported_property`,
`value_out_of_range`, `device_offline`, `bus_timeout`, `modbus_exception`, `internal`. Never
type-check a library's error objects (upstream's bug was `type(x) in […]`) — map the library's
errors onto ours once, in the adapter.

## Boundaries

**RC-10 — Drivers and APIs are disjoint, and `main` statically imports neither.** No driver imports
an API; no API imports a driver. `main` has no static import of any concrete driver or API — both are
resolved from config through a manifest, so `main` cannot become a conduit between them (ADR-0001).
Everything crossing the boundary is a serialisable message: no callbacks, class instances or
Buffers. Why it has to be a message boundary rather than a function call: G-1, ADR-0001.

*Superseded in place, 2026-08-12.* The previous form named `core/` and `server/`, which ADR-0001
dissolved. It was one-directional; this is a partition, and `dependency-cruiser` checks it whole.

**RC-11 — `packages/rig` imports no workspace package and no Modbus client.** The instrument must
not share code with the thing it measures. ADR-0011.

**RC-12 — Parse, don't validate.** Every external input — HTTP body, WS frame, YAML config,
register buffer — goes through a **zod** schema at entry and comes out typed. Nothing downstream
re-checks, and nothing downstream sees `unknown`. Internal message and introspection schemas live in
`@evok-node/messaging`; each API package owns the public wire schema of **its own surface** and no
other. zod for parsing, `z.toJSONSchema()` for fastify's routes. One package holding both the
internal contract and a public surface is the channel through which internal metadata reaches a
compat shape (ADR-0001).

**RC-13 — Normalise identifiers at entry, once.** EVOK accepts `relay`/`input`/`output` alt-names;
they become canonical `DeviceKind` members at the boundary and never travel as raw strings.
Upstream's WS filter silently matched nothing because it compared user strings deep in the stack.

## Drivers, APIs and messages

Added 2026-08-12 with ADR-0001. Numbers appended, nothing renumbered.

**RC-26 — A request envelope carries its own deadline.** There is no way to send one without. This
makes RC-14 structural for the whole message path rather than a rule each call site must remember.

**RC-27 — A driver's query path never blocks on I/O.** A query is a read of state the scan loop
already collected; it never reaches the bus. This is what makes a query timeout meaningful — it can
only mean the driver is wedged, so returning an error is honest rather than a guess.

**RC-28 — Fan-in across drivers uses a per-driver deadline and returns partial results.** A slow or
absent driver marks its own endpoints stale; it never empties the response. All-or-nothing
aggregation is how upstream froze every 1-Wire sensor when one went missing (finding 2.5) and
discarded a whole scan pass on one failing register block (finding 2.6).

**RC-29 — An introspection descriptor's `effect` is mandatory, with no default.** A driver author can
misdeclare it but cannot omit it, and what an API does with it is the API's decision. `run` and
`nv_save` existing as EVOK device types is what leaving this to author discipline produced upstream.

**RC-30 — An API's public schema names no driver type.** Adding a driver must never require an API
release: a new driver contributes data, never schema (ADR-0001). Largely greppable, and a blocking
review comment where it is not.

**RC-31 — An API skips a driver it does not understand, and says so once at startup**, naming the
driver and its type. Skipping is correct — `drivers:` in config is an administrator restriction, not
a capability negotiation. Silent skipping is finding 3.5's shape: a surface that matches nothing and
explains nothing.

**RC-32 — Config validation is fatal at boot and non-fatal on reload.** At boot, exit non-zero with
the reason. On reload, keep running the current configuration and report the rejected one. Same
validation, opposite failure behaviour — and the natural implementation shares one code path and
silently inherits the wrong one.

## Time and effects

**RC-14 — Every wait has a deadline.** No unbounded loop, no promise without a timeout, no
`setTimeout` or `setInterval` without an abort path tied to a lifecycle. No floating promises.

**RC-15 — Inject the clock.** Durations and staleness come from a monotonic source. `Date.now()` is
banned outside logging: an NTP step on a box with no battery clock would corrupt staleness.

**RC-16 — No `sleep()` as a synchronisation primitive, and no `process.env` outside the config
module.** A delay is allowed only as a protocol requirement, with a computed value and a comment
naming the clause (say t3.5) — never a number that made a flaky test pass.

## Addresses, circuits and readings

These are the rules that stop us driving the wrong relay. Every one of them has a real upstream
failure behind it in [research/04](../research/04-known-bugs-and-lessons.md).

**RC-17 — Never derive an identity from a loop counter.** Addresses come from the one audited
address function, which holds the `/16` bank stride and the `%16` mask in exactly one place.

**RC-18 — A duplicate circuit id, or two circuits landing on the same coil or (register, bit), is a
fatal startup error.** Not a warning. Under ADR-0001 this holds in two places, with different
failure behaviour:

- **inside a driver**, checked against its own address tables at init — fatal, always. Internal
  addresses are driver-qualified (ADR-0002), so uniqueness is local and needs no global view.
- **in a projecting API**, checked as injectivity of its projection table — fatal at API start, but
  **not** fatal when a hot-plugged device causes it later. Keep the previous table, serve on, and
  report loudly; a colliding extension must not take down a running API.

**RC-19 — A multi-register value lies wholly inside one register block, read at one frequency.**
Checked when definitions load; a definition that breaks this is rejected, not repaired.

**RC-20 — Every reading carries `value`, `readAt` and `stale`.** No silent zeros, and no value that
stays frozen without saying so. `value` may be a **structure**, not only a scalar — read-only device
configuration is a reading whose value happens to be structured, which is why it needs no fifth data
category beyond G-5's four.

**RC-21 — One event envelope from every source, with `changes` always an array** — 1-Wire included.
Real clients crash on the variant shapes.

## Dependencies

**RC-22 — Prefer a widely used, tested, maintained library** to writing your own — behind an
interface thin enough to swap it out.

## Files and naming

**RC-23 — Naming.** Files `kebab-case.ts`, types `PascalCase`, values and functions `camelCase`.
`SCREAMING_SNAKE` only for real compile-time constants. One exported concept per file, named after
the file. Tests next to their subject: `address-map.ts` → `address-map.test.ts`. No barrel files
except the single package entrypoint — they create import cycles, defeat tree-shaking, and hide
layering violations from review. Directory names are domain terms (`devices/`, `buses/`,
`definitions/`), never `helpers/`, `utils/` or `managers/`; something with no domain home is a
design problem, not a naming problem.

**RC-24 — Two vocabularies, mapped in exactly one place.** The API layer speaks EVOK's words
because clients depend on them. Everything inward speaks ours. The translation lives in
`api-compat` alone, derived from driver introspection rather than hand-maintained (ADR-0003).

Two corollaries, both of which were got wrong once during design and are cheap to get wrong again:
**no driver declares EVOK vocabulary**, and **no driver declares whether an endpoint is
projectable**. A driver publishes its endpoints neutrally; what reaches a public surface is decided
by the API doing the projecting, and by nothing else (ADR-0001).

*Superseded in place, 2026-08-12* — the translation moved out of `@evok-node/protocol`, which
ADR-0001 split.

| Boundary — EVOK-compatible, do not rename | Internal |
|---|---|
| `dev`, `circuit`, `glob_dev_id`, `pending` | `kind`, `id`, `deviceId` |
| `ro`, `do`, `di`, `ai`, `ao`, `wd`, `temp` | `DeviceKind` union |

**RC-25 — Comment the why, never the what.** A comment explaining what a line does is a request to
rename something. Three comments are required: any magic number with its source (a register address
cites the model and map; a timing constant cites the spec clause), any deliberate difference from
EVOK behaviour with a link to the research note, and any workaround for a library bug with the
upstream issue and the condition for removing it. Every `TODO` carries an issue number.
`// TODO: THIS IS HOTFIX !!! REMOVE IT !!!` is what upstream shipped; we do not.
