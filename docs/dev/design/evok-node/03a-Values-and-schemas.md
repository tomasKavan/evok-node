# 03a — Values and schemas

## 1. Scope

What a value is beyond the wire's `Value` (03 §2): its TypeScript type, the runtime `Codec` that decodes, encodes and validates it, and the `ValueSchema` that describes it — built together by `Values`, so the three never drift apart. One vocabulary wherever a value is declared:

| Who | Declares | Who reads the schema |
|---|---|---|
| a driver (05a §3.1) | endpoint values, method arguments and results | apis, the inspector (16) |
| a template, a rule kind (12a §3, 12b §2) | settings, options | the inspector's and the Home UI's forms |
| a module (02 §4) | its config | `main` (validation), the inspector's config forms (02a) |

Published in `@evok-node/module-sdk` (01 §11). Not here: endpoint shapes (05a §3.1), refs (05a §3.10), `LocalizedText` (04 §7), resolving text at the edge (15).

## 2. `ValueType<T>` — a codec and its schema

A value is always declared as a pair: a runtime `Codec<T>` plus a `ValueSchema` describing it. The `Codec` is code and never crosses a boundary; the schema is data and does — in introspection (05a §4), in a form, to a browser.

```ts
// @evok-node/module-sdk
interface Codec<T> {
  decode(wire: Value): T;
  encode(value: T): Value;
  validate(wire: Value): boolean;   // checkValue(schema, wire).length === 0 — §5
}

interface ValueType<T> { readonly codec: Codec<T>; readonly schema: ValueSchema; }
type Infer<C> = C extends ValueType<infer T> ? T : never;

type PrimitiveFormat =
  | 'bool' | 'string' | 'bytes'
  | 'int8' | 'int16' | 'int32' | 'int64'
  | 'uint8' | 'uint16' | 'uint32' | 'uint64'
  | 'float32' | 'float64'
  | 'timestamp'          // uint32 epoch seconds on the wire — same convention as readAt below — decodes to Date
  | 'tlv8' | 'json'      // json is the closed vocabulary's own escape hatch — 06 is the first user
  | 'text'               // a LocalizedText value (04 §7), resolved to one language at the edge (15) — §4
  | 'schema';            // a ValueSchema value, e.g. a template's form (12a §2.4) — §4

interface Annotations {                                // for a human form — §4; never changes what is valid
  readonly label?: LocalizedText;                      // 04 §7
  readonly hint?: LocalizedText;
  readonly helpMd?: LocalizedText;                     // longer help, Markdown — §4
  readonly default?: Value;                            // a struct member a caller may omit; decode fills it in
  readonly optional?: boolean;                         // a struct member a caller may omit; decode leaves it absent
  readonly actor?: true;                               // the caller, filled by the api — 13 §5; Values.actor() only
  readonly sensitive?: true;                           // never read back: a password, a token — §4
}

interface Semantics extends Annotations {
  readonly unit?: string;                            // 'mV' | 'uA' | '%' ... — descriptive only, never enforced by validate()
  readonly min?: number;
  readonly max?: number;
  readonly step?: number;
  readonly maxLength?: number;                       // string/bytes length, array length, or record entries
  readonly enumValues?: readonly (string | number)[];
  readonly pattern?: string;                         // ECMAScript regex source, matched against the whole string
  readonly scaler?: number;                          // engineering value = raw wire number * scaler; omitted ⇒ 1
  readonly enumLabels?: Readonly<Record<string, LocalizedText>>;      // §4 — one per enumValues entry
  readonly ref?: { readonly type: string; readonly filter?: Value };  // 05a §3.10 — the value is an object's id
}

type ValueSchema = PrimitiveSchema | ArraySchema | RecordSchema | StructSchema | UnionSchema | VoidSchema;

interface PrimitiveSchema extends Semantics { readonly type: 'primitive'; readonly format: PrimitiveFormat; }
interface ArraySchema     extends Semantics { readonly type: 'array'; readonly items: ValueSchema; }
interface RecordSchema    extends Semantics { readonly type: 'record'; readonly values: ValueSchema; readonly keys?: { readonly pattern?: string; readonly maxLength?: number }; }
interface StructSchema    extends Annotations { readonly type: 'struct'; readonly fields: Readonly<Record<string, ValueSchema>>; }
interface UnionSchema     extends Annotations { readonly type: 'union'; readonly tag: string; readonly variants: Readonly<Record<string, ValueSchema>>; }
interface VoidSchema                        { readonly type: 'void'; }   // a method's result only — §4
```

`Semantics` tells a generic consumer how to render a control correctly (05a §3.4's `AO`/`DO`). Whether a limit is also enforced depends on where the value is used (§5.1). `int64`/`uint64` decode to `bigint`, never `number`: `Value` (03 §2) has no `bigint` arm, so their wire form is a decimal string, the same JSON-safe shape as everything else on this boundary — `BigInt(str)` is the whole decode, no big-number library needed. `timestamp` costs nothing new either: it reuses `readAt`'s own existing epoch-seconds convention, just typed as `Date` instead of a raw number callers had to interpret themselves.

## 3. `Values` — the one factory

`Values` is the one place every leaf format and every combinator lives, so an author never hand-writes a `Codec` or a `ValueSchema` separately — illustrative only, the mechanical parts of the generics are elided the same way 05a §3.3's `DeviceType` example elides them:

```ts
// @evok-node/module-sdk — illustrative only
const Values: {
  readonly bool: (s?: Semantics) => ValueType<boolean>;
  readonly string: (s?: Semantics) => ValueType<string>;
  readonly bytes: (s?: Semantics) => ValueType<Uint8Array>;
  readonly int8: (s?: Semantics) => ValueType<number>;
  readonly int16: (s?: Semantics) => ValueType<number>;
  readonly int32: (s?: Semantics) => ValueType<number>;
  readonly int64: (s?: Semantics) => ValueType<bigint>;
  readonly uint8: (s?: Semantics) => ValueType<number>;
  readonly uint16: (s?: Semantics) => ValueType<number>;
  readonly uint32: (s?: Semantics) => ValueType<number>;
  readonly uint64: (s?: Semantics) => ValueType<bigint>;
  readonly float32: (s?: Semantics) => ValueType<number>;
  readonly float64: (s?: Semantics) => ValueType<number>;
  readonly timestamp: (s?: Semantics) => ValueType<Date>;
  readonly tlv8: (s?: Semantics) => ValueType<Uint8Array>;
  readonly json: (s?: Semantics) => ValueType<unknown>;
  readonly void: ValueType<void>;   // a `method` with nothing meaningful to return on success — schema { type: 'void' }
  readonly text: (s?: Semantics) => ValueType<LocalizedText>;
  readonly schema: (s?: Semantics) => ValueType<ValueSchema>;
  readonly actor: () => ValueType<Actor | undefined>;   // optional struct { realm, id?, name? }, annotated actor — 13 §5
  optional<T>(c: ValueType<T>): ValueType<T | undefined>;   // sets the member's `optional` — §4
  struct<F extends Record<string, ValueType<unknown>>>(fields: F, a?: Annotations): ValueType<{ readonly [K in keyof F]: Infer<F[K]> }>;
  record<V>(values: ValueType<V>, s?: Semantics & { keys?: RecordSchema['keys'] }): ValueType<Readonly<Record<string, V>>>;
  array<T>(items: ValueType<T>, s?: Semantics): ValueType<readonly T[]>;
  union<V extends Record<string, ValueType<unknown>>>(tag: string, variants: V): ValueType<UnionOf<V>>;   // UnionOf<V> tags each Infer<V[K]> with { [tag]: K } — mechanical, omitted here
};
```

`union`'s decoded value always carries the discriminant itself, merged in — `Values.union('mode', { voltage10: Values.struct({...}) })` decodes to `{mode: 'voltage10', ...}`, never a bare variant the caller has to re-tag by hand. 05a §3.4 works through a full example. Every declared value type comes from composing `Values`' members — never a bare object literal claiming a `schema` it doesn't back with a real `Codec`, and never a `Codec` written by hand without the matching `schema`. Neither `bindDevice()` (05a §3.5) nor `main` (02 §4) can check the two agree; keeping them paired through `ValueType` rather than authored separately is what actually prevents drift.

`record` is a map: keys chosen by the user, values of one type. `struct` is the opposite — keys fixed by the author, each with its own type.

| | Keys chosen by | Values | Example | Form (§4) |
|---|---|---|---|---|
| `struct` | the author | each key its own type | `transport: { host, port }` | one input per field |
| `record` | the user | one type | `rates: { fast: 100, medium: 500 }` | key/value rows |
| `array` | nobody — position | one type | `devices: [ {…}, {…} ]` | ordered rows |

A `record` when items are keyed by a unique name; an `array` when they have no natural name or their order matters.

## 4. Forms — annotations, defaults, optional members

A schema also describes what a human fills in, so any UI renders an input for a method's arguments, a template's settings, a rule's options (12a §2.4) or a module's config (02 §4) from the schema alone:

```ts
store: method('mutates', Values.void, Values.struct({
  romId: Values.string({ label: 'Sensor', ref: { type: 'onewire.candidate' } }),        // 05a §3.10
  label: Values.string({ maxLength: 32, default: '', label: { en: 'Label', cs: 'Popis' } }),
  note:  Values.optional(Values.string({ label: 'Note' })),
})),
```

| Struct member | Caller may omit it | After decode |
|---|---|---|
| `Values.bool()` | no | as sent |
| `Values.bool({ default: false })` | yes | `false` |
| `Values.optional(Values.bool())` | yes | absent |

- Annotations never change what is valid. `default` and `optional` only decide what a caller may omit; limits are §5's.
- `default` and `optional` mean something only on a struct member. Both on one member is a packaging mistake, rejected when the value type is built.
- `optional` here is a value a caller may omit. `optional()` on a `DeviceType` field (05a §3.3) is an endpoint a device may not have — a different thing.
- `enumLabels` has exactly the keys of `enumValues`.
- `LocalizedText` travels in full, every language; the WS API resolves it for the session's language (15) — `label`, `hint`, `helpMd`, `enumLabels`. A value that is itself user-facing text has format `text`; a value that is itself a schema (a template's form) has format `schema`, so the edge finds the text inside it too.
- `label` and `hint` are plain text, short enough for a list, a picker or a tooltip. `helpMd` is longer help in Markdown, shown in a help panel. A UI renders it without raw HTML: a plugin wrote it.
- `actor` marks the member an api fills with its own caller and never relays from a client (13 §5). Only `Values.actor()` sets it, and only as a struct member of a method's arguments; anywhere else it is a packaging mistake, rejected when the value type is built.
- `sensitive` marks a value that is never read back — a password, a token. Legal on a `string` or `bytes` member only; anywhere else it is rejected when the value type is built. Config is its user: 02a keeps such a value in the secrets file and reads it back as a ref.
- `{ type: 'void' }` is `Values.void`'s schema — a method's result only, on the wire a success with no body. Never a struct member, an array item, or a reading's or channel's schema.

How a generic form renders each schema:

| Schema | Input |
|---|---|
| `primitive` | by `format`, `enumValues`, `unit`, `min`/`max`/`step` |
| `struct` | one input per field |
| `record` | key/value rows; add and remove; keys checked against `keys` |
| `array` | ordered rows; add, remove, reorder |
| `union` | a selector for `tag`, then that variant's fields only |
| a `ref` | a picker filled from `$refs` (05a §3.10) |

## 5. Checking — `checkValue` and `Issue`

```ts
// @evok-node/module-sdk
function checkValue(schema: ValueSchema, wire: Value, opts?: { limits?: 'advisory' | 'binding' }): Issue[];   // default 'advisory'

interface Issue {
  readonly path: readonly (string | number)[];   // [] — the value itself; ['transport', 'port']; ['devices', 0, 'unit']
  readonly code: IssueCode;
  readonly message: LocalizedText;               // module-sdk ships one per code; a 'rule' issue brings its own
  readonly rule?: string;                        // code 'rule' only: the rule's id, e.g. 'not-with-autogen'
}

type IssueCode =
  | 'required' | 'type' | 'union-tag'                       // shape — always checked
  | 'unknown-field'                                         // only when binding (§5.1)
  | 'min' | 'max' | 'max-length' | 'pattern' | 'enum'       // limits — only when binding (§5.1)
  | 'sensitive-missing'                                     // a secret ref with no stored value — 02a
  | 'rule';                                                 // ModuleDescriptor.rules (02 §4), main's cross-instance checks (02a §2.4)
```

- **Data in, issues out.** No plugin code runs, so the same function runs in `main`, in the `main` driver and in a browser — a form is checked on every edit without asking the daemon.
- **Every issue at once**, never only the first: a form marks every wrong field.
- **A format's own range is shape.** `70000` for a `uint16` is `max` in both modes — the format cannot hold it.
- **Unknown struct fields are an issue when binding**: a typo in config (`scna:` for `scan:`) never passes silently. Advisory leaves them alone.
- `Codec.validate(wire)` is `checkValue(schema, wire).length === 0` — advisory.

```yaml
transport: { host: 127.0.0.1, port: 70000, timeout: 50 }
devices: [ { unit: 0, definition: modbus/unipi/brain-s107 } ]
```

```ts
checkValue(schema, body, { limits: 'binding' }) → [
  { path: ['transport', 'port'],    code: 'max',           message: 'At most 65535' },
  { path: ['transport', 'timeout'], code: 'unknown-field', message: 'Unknown field' },
  { path: ['devices', 0, 'unit'],   code: 'min',           message: 'At least 1' },
]
```

### 5.1. Advisory or binding

| Value | Limits, unknown fields | Why |
|---|---|---|
| an endpoint's value, a `SET` payload, a method's arguments | advisory | the device behind it enforces its own limits; a second copy here would drift |
| a module's config; the home driver's template settings and rule options (12a §3, 12b §2) | binding | a human's input with nothing behind it |

### 5.2. Where it runs

```
inspector form, every edit        checkValue(schema, draft, { limits: 'binding' })     no round trip
main driver validate (02a)         checkValue → decode → rules(config) → main's cross-instance checks (02 §5)
main at startup (02 §5)            the same chain
driver-kit, SET/CALL payload       checkValue(schema, payload) → bad-payload (05a §3.5)
```

## 6. Testing

Tier 1 (unit; `basics/03-Testing.md`), `module-sdk` only — no driver, no daemon:

- Forms (§4): a struct member with `default` may be omitted and decodes to it; an `optional` one decodes absent; omitting a plain member fails `validate`; `default` with `optional` is rejected when the value type is built; `Values.void`'s schema reaches the wire as `{ type: 'void' }`.
- `record` (§3): a key outside `keys.pattern` is `pattern` at that key's path; `maxLength` counts entries.
- `checkValue` (§5): one fixture per `IssueCode`, asserting `path` and `code`; every issue reported at once; advisory skips `unknown-field` and `min`/`max`/`max-length`/`pattern`/`enum`, but never a format's own range; `Codec.validate` agrees with `checkValue` on every fixture.
- `sensitive` (§4) on anything but `string` or `bytes` is rejected when the value type is built.
- Annotations (§4): `label`, `hint`, `helpMd` and `enumLabels` reach the schema unchanged — resolving them is the edge's job (15).
