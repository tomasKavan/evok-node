# Code rules

Binding. Most are enforced; the enforcement mechanism is named so you can check locally.

## Enforcement first

A rule that is only prose gets ignored — by agents and humans alike. **If a rule can be a lint
rule, it must be a lint rule.** Prose here exists only for rules a linter cannot express.

| Tool | Enforces |
|---|---|
| `tsc --strict` + `noUncheckedIndexedAccess`, `exactOptionalPropertyTypes`, `noImplicitOverride`, `noFallthroughCasesInSwitch` | type-level invariants |
| `eslint` + `@typescript-eslint` (type-checked config) | no `any`/`as`/`!`, no floating promises, exhaustive switches, import restrictions |
| **`dependency-cruiser`** | package layering, no cycles, no undeclared imports |
| `commitlint` | Conventional Commits |
| `prettier` | formatting — never discussed in review |

**`dependency-cruiser` is load-bearing here.** We chose npm workspaces, whose flat
`node_modules` lets a package import something it never declared. Without the layering rules
encoded there, nothing stops `core` from quietly importing `server`.

## Types

**Brand anything that is a number with a meaning.** Register addresses, coil addresses, unit ids
and bit offsets are all `number` structurally, and upstream EVOK's worst bug was writing a coil
address where a register address belonged.

```ts
type Brand<T, B> = T & { readonly __brand: B };
export type RegisterAddress = Brand<number, 'RegisterAddress'>;
export type CoilAddress     = Brand<number, 'CoilAddress'>;
export type UnitId          = Brand<number, 'UnitId'>;
export type BitOffset       = Brand<number, 'BitOffset'>;
export type Millis          = Brand<number, 'Millis'>;
export type Circuit         = Brand<string, 'Circuit'>;
```

Constructors live with the type and validate range (`unitId` 0–255, `bitOffset` 0–15). There is
no unchecked path to a branded value.

**Discriminated unions over booleans and optional fields.** A device is
`{kind:'di', …} | {kind:'ao', …}`, not one interface with everything optional. Then a `switch`
with no `default` plus `noFallthroughCasesInSwitch` makes a missed case a compile error — which
is exactly the class of bug that left EVOK's `ds_mode` permanently stuck.

**Decode is a total function.** `decode(registers) => State`, every branch returning a value.
Never mutate state in place with implicit fall-through.

**`readonly` by default.** Definitions are `readonly` types *and* frozen at runtime. Upstream
needed a `copy()`→`deepcopy()` fix because two slaves shared one mutable array; `readonly`
prevents that at compile time.

## Errors

Two categories, two mechanisms:

- **Expected failure → a value.** `Result<T, E>` as a discriminated union. The compiler must
  make ignoring the error arm impossible.
- **Programmer error → `throw`.** Broken invariant, impossible state. Never caught for control
  flow.

Error *kinds* are string-literal unions, not classes — they cross the API boundary and must
serialise. Taxonomy at minimum: `bad_request`, `unknown_circuit`, `unsupported_property`,
`value_out_of_range`, `device_offline`, `bus_timeout`, `modbus_exception`, `internal`.

Never exact-type-check a library's errors (`type(x) in […]` was upstream's bug). Normalise a
library's error taxonomy into ours at the adapter boundary, once.

## Boundaries

**Parse, don't validate.** Every external input — HTTP body, WS frame, YAML config, register
buffer — passes through a **zod** schema at ingress and becomes a typed value. Nothing
downstream re-checks, and nothing downstream sees `unknown`.

Wire schemas live in `@evok-node/protocol` and are the single source of truth: zod for internal
parsing, `z.toJSONSchema()` for fastify's route schemas. One declaration, both uses.

**Normalise identifiers once, at ingress.** EVOK accepts `relay`/`input`/`output` alt-names;
they become canonical `DeviceKind` union members at the boundary and never travel as raw
strings. Upstream's WS filter silently matched nothing precisely because it compared
user strings deep in the stack.

## Time and effects

- **Inject the clock.** Durations and staleness use a monotonic source; `Date.now()` is banned
  outside logging (NTP steps on an embedded box with no RTC would otherwise corrupt staleness).
- **No `process.env` outside the config module.**
- **No floating promises**, and every `setTimeout`/`setInterval` has an abort path tied to a
  lifecycle.
- **No `sleep()` as a synchronisation primitive.** If you need a delay, it is a protocol
  requirement with a computed value and a comment naming the spec clause (e.g. t3.5) — never a
  number that made a flaky test pass.

## Files and naming

- Files `kebab-case.ts`. Types `PascalCase`. Values and functions `camelCase`.
  `SCREAMING_SNAKE` only for genuine compile-time constants.
- **One exported concept per file**, named after the file.
- Tests colocated: `address-map.ts` → `address-map.test.ts`.
- **No barrel files** except the single package entrypoint. Barrels create import cycles and
  defeat tree-shaking; in a monorepo they also hide layering violations from review.
- Directory names are domain terms, not patterns: `devices/`, `buses/`, `definitions/` — not
  `helpers/`, `utils/`, `managers/`. If something genuinely has no domain home, that is a design
  smell, not a naming problem.

## Vocabulary

Two vocabularies, mapped in exactly one place:

| Boundary (EVOK-compatible, do not rename) | Internal |
|---|---|
| `dev`, `circuit`, `glob_dev_id`, `pending` | `kind`, `id`, `deviceId` |
| `ro`, `do`, `di`, `ai`, `ao`, `wd`, `temp` | `DeviceKind` union |

The API layer speaks EVOK's vocabulary because clients depend on it. Everything inward speaks
ours. The translation lives in `@evok-node/protocol` and nowhere else.

## Comments

Comment the **why**, never the **what**. A comment explaining what a line does is a request to
rename something. Comments that *are* required:

- any magic number, with its source (a register address gets the model and map reference; a
  timing constant gets the spec clause);
- any deliberate deviation from EVOK behaviour, linking the research note;
- any workaround for a library bug, linking the upstream issue and stating the removal condition.

`TODO` must carry an issue number. `// TODO: THIS IS HOTFIX !!! REMOVE IT !!!` is what upstream
shipped to production; we do not.
