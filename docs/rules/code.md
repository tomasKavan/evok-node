# Code rules

Binding. Cite as **RC-N**. Breaking one is a blocking review comment; the enforcement column says
what catches it, so you can check before pushing.

**If a rule can be a lint rule, it must be a lint rule.** Prose-only rules get ignored — by agents
and humans alike. What follows is prose only where a linter cannot express it.

| Tool | Catches |
|---|---|
| `tsc --strict` + `noUncheckedIndexedAccess`, `exactOptionalPropertyTypes`, `noImplicitOverride`, `noFallthroughCasesInSwitch` | type-level rules |
| `eslint` + `@typescript-eslint`, type-checked | RC-2, RC-14, RC-15, RC-16, RC-23 |
| `dependency-cruiser` | RC-10, RC-11, import cycles, undeclared imports |
| `prettier` | formatting — never discussed in review |

`dependency-cruiser` is load-bearing. npm workspaces give every package a flat `node_modules`, so
without it nothing stops `core` importing `server`.

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
export type Circuit         = Brand<string, 'Circuit'>;
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

**RC-10 — `core/` never imports `api/`, `server/` or `inspector/`, and everything crossing the
core↔API boundary is a serialisable message.** No callbacks, class instances or Buffers. Why it has
to be a message boundary rather than a function call: G-1, ADR-0001.

**RC-11 — `packages/rig` imports no workspace package and no Modbus client.** The instrument must
not share code with the thing it measures. ADR-0007.

**RC-12 — Parse, don't validate.** Every external input — HTTP body, WS frame, YAML config,
register buffer — goes through a **zod** schema at entry and comes out typed. Nothing downstream
re-checks, and nothing downstream sees `unknown`. Wire schemas live in `@evok-node/protocol` and are
the one source of truth: zod for internal parsing, `z.toJSONSchema()` for fastify's routes.

**RC-13 — Normalise identifiers at entry, once.** EVOK accepts `relay`/`input`/`output` alt-names;
they become canonical `DeviceKind` members at the boundary and never travel as raw strings.
Upstream's WS filter silently matched nothing because it compared user strings deep in the stack.

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
fatal startup error.** Not a warning.

**RC-19 — A multi-register value lies wholly inside one register block, read at one frequency.**
Checked when definitions load; a definition that breaks this is rejected, not repaired.

**RC-20 — Every reading carries `value`, `readAt` and `stale`.** No silent zeros, and no value that
stays frozen without saying so.

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
`@evok-node/protocol` and nowhere else.

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
