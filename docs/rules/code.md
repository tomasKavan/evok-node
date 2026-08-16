# Code rules

Binding. Cite as **RCD-N**. Breaking one is a blocking review comment; the enforcement column says
what catches it, so you can check before pushing.

**These rules are about how we write TypeScript, and nothing else.** No rule here names a package, a
driver, an API surface or any other thing this project happens to contain — a rule that needs to do
that is a package rule and lives in [`packages/`](packages/README.md). Layering is not stated here
either: it is a table in `.dependency-cruiser.cjs`, and a lint rule beats a paragraph.

**If a rule can be a lint rule, it must be a lint rule.** Prose-only rules get ignored — by agents
and humans alike. What follows is prose only where a linter cannot express it.

| Tool | Catches |
|---|---|
| `tsc --strict` + `noUncheckedIndexedAccess`, `exactOptionalPropertyTypes`, `noImplicitOverride`, `noFallthroughCasesInSwitch` | type-level rules |
| `eslint` + `@typescript-eslint`, type-checked | RCD-2, RCD-11, RCD-12, RCD-13, RCD-15 |
| `dependency-cruiser` | layering, import cycles, undeclared imports |
| `prettier` | formatting — never discussed in review |

Each rule says what went wrong without it. Where the failure was upstream EVOK's, the finding number
points at [research/04](../research/04-known-bugs-and-lessons.md); that is evidence for the rule, not
a rule about EVOK.

## Types

**RCD-1 — Brand every number that means something.** A quantity whose unit or address space matters
is not a `number`. Two `number`s of different kinds are interchangeable to the compiler, and writing
one where the other belonged was upstream's worst bug.

```ts
type Brand<T, B> = T & { readonly __brand: B };
export type Millis = Brand<number, 'Millis'>;
export type Seq    = Brand<number, 'Seq'>;
```

The constructor lives with the type and checks range. There is no unchecked way to get a branded
value.

**RCD-2 — No `any`, no `as`, no `!`** outside generated code. Parse at the boundary (RCD-10), and
after that the type is real.

**RCD-3 — Discriminated unions, not optional fields.** A variant type is
`{kind:'a', …} | {kind:'b', …}`, never one interface with everything optional. A `switch` with no
`default`, in a function with a declared return type, then makes a missing case a compile error.

**RCD-4 — `readonly` by default, and anything loaded from outside is frozen once loaded.** Frozen
*per load*, not once per process — reloading must produce a new frozen value rather than mutate the
old one. Upstream needed a `copy()`→`deepcopy()` fix because two consumers shared one mutable array.

**RCD-5 — A decode returns a value on every path.** `decode(input) => Output`. Never mutate state in
place and fall through.

## Errors

**RCD-6 — Expected failure is a value; a bug is a `throw`.** Expected failure returns
`{ok:true, …} | {ok:false, kind:…}`, and the compiler must make ignoring the failure arm impossible.
`throw` is for broken invariants only, and is never caught for control flow.

**RCD-7 — A protocol-level error response is a failure.** Never a value a caller can mistake for
success. A wire protocol that reports errors in-band (a Modbus exception PDU, an HTTP 4xx) hands you
a well-formed reply that means *no*; the type must say so.

**RCD-8 — No empty `catch {}` on an event or delivery path.** Log and count, with dedup.

**RCD-9 — Error kinds are string-literal unions, not classes.** They cross serialisation boundaries,
so they must survive one. Never type-check a library's error objects — upstream's bug was
`type(x) in […]`, which broke the moment the library reorganised its exceptions. Map a library's
errors onto ours exactly once, in the adapter that owns that library.

## Boundaries

**RCD-10 — Parse, don't validate.** Every external input — HTTP body, socket frame, config file,
byte buffer — goes through a **zod** schema at entry and comes out typed. Nothing downstream
re-checks, and nothing downstream sees `unknown`. zod for parsing, `z.toJSONSchema()` where a JSON
Schema is needed.

## Time and effects

**RCD-11 — Every wait has a deadline.** No unbounded loop, no promise without a timeout, no
`setTimeout` or `setInterval` without an abort path tied to a lifecycle. No floating promises.

**RCD-12 — Inject the clock.** Durations and staleness come from a monotonic source. `Date.now()` is
banned outside logging: an NTP step on a box with no battery clock would corrupt every age
computed from it.

**RCD-13 — No `sleep()` as a synchronisation primitive, and no `process.env` outside the config
module.** A delay is allowed only as a protocol requirement, with a computed value and a comment
naming the clause it comes from — never a number that made a flaky test pass.

## Dependencies

**RCD-14 — Prefer a widely used, tested, maintained library** to writing your own — behind an
interface thin enough to swap it out.

## Files and naming

**RCD-15 — Naming.** Files `kebab-case.ts`, types `PascalCase`, values and functions `camelCase`.
`SCREAMING_SNAKE` only for real compile-time constants. One exported concept per file, named after
the file. Tests next to their subject: `address-map.ts` → `address-map.test.ts`. No barrel files
except the single package entrypoint — they create import cycles, defeat tree-shaking, and hide
layering violations from review. Directory names are domain terms, never `helpers/`, `utils/` or
`managers/`; something with no domain home is a design problem, not a naming problem.

## Comments

**RCD-16 — Comment the why, never the what — and as briefly as it can be said.** A comment
explaining what a line does is a request to rename something. Where a comment is required it is one
line if one line will do; a paragraph above a function is almost always a sign the function should be
split or renamed instead.

Four comments are required, and they are the only ones that are:

- any magic number, with its source — an address cites the document it came from, a timing constant
  cites the spec clause;
- any deliberate difference from the behaviour we are replacing, with a link to the research note;
- any workaround for a library bug, with the upstream issue and the condition for removing it;
- every `TODO`, with an issue number. `// TODO: THIS IS HOTFIX !!! REMOVE IT !!!` is what upstream
  shipped; we do not.
