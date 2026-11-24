# 13c — Localization

## 1. Scope

The `l10n` WS extension (15 §7): it picks a language for each session and resolves every `LocalizedText` (04 §7) the session receives. Drivers always answer in every language, so introspection stays one payload shared by all sessions; l10n turns it into one language at the edge.

It assumes 04 §7 (`LocalizedText`, `resolveText`), 03a §4 (annotations, formats `text` and `schema`) and 15 (the extension contract).

**Not here:**

- Formatting numbers, dates and units — the UI's.
- Translation catalogs. A module ships its texts inline, every language it has; there is no way to add a language to a module without a new release.

## 2. Session language

A session's language is a list of BCP 47 tags, most wanted first:

```
hello.lang  →  else the upgrade's Accept-Language, by q  →  else config defaultLang  →  'en'
```

```ts
// 04 §7
function resolveText(text: LocalizedText, langs: readonly LanguageTag[]): string;
// for each tag: the tag, then its primary subtag ('cs-CZ' → 'cs'); then 'en'
```

```jsonc
→ { "type": "hello", "v": 1, "lang": ["de", "cs"] }       // a module with cs and en answers cs
→ { "type": "hello", "v": 1, "lang": "cs" }               // one tag is a list of one
→ { "type": "hello", "v": 1, "lang": "*" }                // no resolution — every language, as drivers send it
```

- **`*`** is for a client that serves text further: a PLC importing another PLC's devices (12a §4b) shows them to its own clients in their language. The `*` of `Accept-Language` is ignored.
- At most 8 tags; the rest are dropped. A malformed tag is dropped.

## 3. Control messages

l10n owns `lang` and `setLang` (15 §7):

```jsonc
← { "type": "lang", "lang": ["cs", "en"] }     // in onConnection, before the server hello; again after each setLang
→ { "type": "setLang", "lang": ["en"] }        // any time after the server hello
```

After a `lang` that changed, the client fetches introspection again — `GET <driver>:$introspect` without `since` — and every value it shows. l10n does not push it.

## 4. What is resolved

Only what a schema marks, so l10n never guesses which string is text:

| Where | Resolved | Hook |
|---|---|---|
| introspection | `label`, `hint`, `helpMd`, `enumLabels` in every schema (03a §4) | `afterIntrospect`, `onPush` for its changes |
| a value whose schema has format `text` | the value | `afterRequest`, `onPush` |
| a value whose schema has format `schema` | the annotations inside it (a template's form) | `afterRequest`, `onPush` |
| a `$refs` answer (05a §3.10) | each `RefChoice.label` | `afterRequest` |

- **The schema of a value** comes from the endpoint's introspection: a reading's or channel's schema for `GET`, `SET` and events, a method's result for `CALL`. Text nested in a struct, record or array is found by walking the value along its schema.
- **A module's rule:** `LocalizedText` inside a value reaches clients resolved only if its schema member is `Values.text()` — e.g. `PluginMeta` in the `main` driver's `plugins` reading (02a, 02b §5.1).

```jsonc
// driver: { "label": { "en": "Relay", "cs": "Relé" }, "format": "bool" }
// session ["cs"]:  { "label": "Relé", "format": "bool" }
// session "*":     { "label": { "en": "Relay", "cs": "Relé" }, "format": "bool" }
```

**Never resolved:** text a user typed (a device name — 04 §7), log messages, and an error's `detail`. A UI shows its own text for an error's `kind` and `domainErrorKind`.

## 5. Order and cache

- **l10n is listed after `acl`.** After-hooks run in reverse list order (15 §7), so l10n resolves first and `acl` filters the resolved payload per session.
- **One resolved introspection per `(driver, generation, langs)`,** in memory, shared by every session with that language list. At most `cacheEntries`; the least recently used goes. A new `generation` (03 §5a) replaces the driver's entries.
- **Values** are resolved per message; nothing is cached.

```yaml
extensions:
  - { use: auth, config: { idp: auth } }
  - { use: acl,  config: { idp: auth } }
  - { use: l10n, config: { defaultLang: cs } }
```

## 6. Config

```ts
const L10nConfig = Values.struct({
  defaultLang:  Values.string({ default: 'en', label: 'Default language', hint: 'BCP 47, e.g. cs' }),
  cacheEntries: Values.uint16({ default: 64 }),
});
```

Without l10n in an api's list, the api relays every `LocalizedText` as drivers send it, as for `*`.

## 7. Testing

Tier 1 (basics/03), with a fixture driver whose schemas and values carry `LocalizedText`, and ws-kit:

- **Fallback:** `['de', 'cs']` gets `cs`; `cs-CZ` gets `cs`; a language no text has gets `en`; no `lang` and no `Accept-Language` gets `defaultLang`.
- **`*`:** schemas and values arrive as the driver sent them.
- **`setLang`:** a `lang` message follows; a full `GET $introspect` then arrives in the new language.
- **Formats:** a `text` value, the annotations inside a `schema` value and a `$refs` label are resolved; a plain `string` member holding a record is not.
- **Cache:** two sessions with one language list share one entry; with `acl` before it, each still sees only what its grants allow.
