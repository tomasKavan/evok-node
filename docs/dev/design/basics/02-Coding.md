# Coding and code rules

**If a rule can be a lint rule, it must be a lint rule**
Prose-only rules get ignored — by agents and humans alike. What follows is prose only where a linter cannot express it.

| Tool | Catches |
|---|---|
| `tsc --strict` + `noUncheckedIndexedAccess`, `exactOptionalPropertyTypes`, `noImplicitOverride`, `noFallthroughCasesInSwitch` | type-level rules |
| `eslint` + `@typescript-eslint`, type-checked | lint rules |
| `dependency-cruiser` | layering, import cycles, undeclared imports |
| `prettier` | formatting — never discussed in review |

## 1. Types

### 1.1. Brand every number that means something
A quantity whose unit or address space matters is not a `number`. Two `number`s of different kinds are interchangeable to the compiler, and writing one where the other belonged was upstream's worst bug.

```ts
type Brand<T, B> = T & { readonly __brand: B };
export type Millis = Brand<number, 'Millis'>;
export type Seq    = Brand<number, 'Seq'>;
```

The constructor lives with the type and checks range. There is no unchecked way to get a branded value.

### 1.2. No `any`, no `as`, no `!`
No `any`, no `as`, no `!` outside generated code. Parse at the boundary (RCD-10), and after that the type is real.

### 1.3. Discriminated unions, not optional fields.
A variant type is `{kind:'a', …} | {kind:'b', …}`, never one interface with everything optional. A `switch` with no `default`, in a function with a declared return type, then makes a missing case a compile error.

### 1.4. `readonly` by default, and anything loaded from outside is frozen once loaded
Frozen *per load*, not once per process — reloading must produce a new frozen value rather than mutate the old one. Upstream needed a `copy()`→`deepcopy()` fix because two consumers shared one mutable array.

### 1.5. A decode returns a value on every path
`decode(input) => Output`. Never mutate state in place and fall through.

## 2. Errors

### 2.1. Expected failure is a value; a bug is a `throw`.
Expected failure returns `{ok:true, …} | {ok:false, kind:…}`, and the compiler must make ignoring the failure arm impossible. `throw` is for broken invariants only, and is never caught for control flow.

### 2.2. A protocol-level error response is a failure.
Never a value a caller can mistake for success. A wire protocol that reports errors in-band (a Modbus exception PDU, an HTTP 4xx) hands you a well-formed reply that means *no*; the type must say so.

### 2.3. No empty `catch {}` on an event or delivery path.
Log and count, with dedup.

### 2.4. Error kinds are string-literal unions, not classes.
They cross serialisation boundaries, so they must survive one. Never type-check a library's error objects — upstream's bug was `type(x) in […]`, which broke the moment the library reorganised its exceptions. Map a library's errors onto ours exactly once, in the adapter that owns that library.

## 3. Boundaries

### 3.1. Parse, don't validate
Every external input — HTTP body, socket frame, config file, byte buffer — goes through a **zod** schema at entry and comes out typed. Nothing downstream re-checks, and nothing downstream sees `unknown`. zod for parsing, `z.toJSONSchema()` where a JSON Schema is needed.

## 4. Time and effects

### 4.1. Every wait has a deadline
No unbounded loop, no promise without a timeout, no `setTimeout` or `setInterval` without an abort path tied to a lifecycle. No floating promises.

### 4.2. Inject the clock
Durations and staleness come from a monotonic source. `Date.now()` is banned outside logging: an NTP step on a box with no battery clock would corrupt every age computed from it.

### 4.3. No `sleep()` as a synchronisation primitive, and no `process.env` outside the config module
A delay is allowed only as a protocol requirement, with a computed value and a comment naming the clause it comes from — never a number that made a flaky test pass.

## 5. Dependencies

### 5.1. Prefer a widely used, tested, maintained library
Prefer a widely used, tested, maintained library to writing your own — behind an interface thin enough to swap it out.

## 6. Files and naming

### 6.1. Naming
Files `kebab-case.ts`, types `PascalCase`, values and functions `camelCase`. `SCREAMING_SNAKE` only for real compile-time constants. One exported concept per file, named after the file. Tests next to their subject: `address-map.ts` → `address-map.test.ts`. No barrel files except the single package entrypoint — they create import cycles, defeat tree-shaking, and hide layering violations from review. Directory names are domain terms, never `helpers/`, `utils/` or `managers/`; something with no domain home is a design problem, not a naming problem.

## 7. Comments

### 7.1. Comment the why, never the what — and as briefly as it can be said
A comment explaining what a line does is a request to rename something. Where a comment is required it is one line if one line will do; a paragraph above a function is almost always a sign the function should be split or renamed instead.

Four comments are required, and they are the only ones that are:

- any magic number, with its source — an address cites the document it came from, a timing constant cites the spec clause;
- any deliberate difference from the behaviour we are replacing, with a link to the research note;
- any workaround for a library bug, with the upstream issue and the condition for removing it;
- every `TODO`, with an issue number. `// TODO: THIS IS HOTFIX !!! REMOVE IT !!!` is what upstream shipped; we do not.

## 8. Tech stack

Mandatory minimum:
- Node 24 (LTS)
- `zod` for validations
- Vue.js 3 and Prime Vue v5 for inspector SPA
- TBD
