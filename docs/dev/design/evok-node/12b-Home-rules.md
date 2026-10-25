# 12b — Home rules

## 1. Scope

A **rule** controls home devices (12a §2) when another home device changes. Rules are part of the home driver (12a): same package, same KV namespace (06), same failure domain.

- Only home devices, of any origin (12a §1), `exposed: false` and `controllable: false` ones included (12a §2.1). Never a plain driver-kit device: a rule that switches a relay uses the `OnOffLight` assembled from it.
- A rule runs on the PLC that stores it. A `remote` device can be in a rule here; the remote's own rules stay the remote's (12a §4b).
- A user never writes code. They pick a **rule kind** (§2) and fill in its slots and options (§3), in the Inspector UI or the Home UI (§8).
- A run is short: no delays, no timers, no scheduling inside a rule. Anything that needs time is a device — a `TimerRelay` (12c-05), as in the built-in pair `on-and-set-delay-off` and `delay-off` (§2.1):

```
rule A:  hall switch short press  →  hall light on,  hall timer restart({ ms: 120000 })
rule B:  hall timer elapsed       →  hall light off
```

## 2. Rule kinds

A **rule kind** is the recipe: which devices may trigger a rule, which devices it controls, what a user fills in, and the function that runs. Like a template (12a §3), it is a manifest-loaded, `kind`-resolved module (02 §4), so a plugin can add one without touching this package:

```json
{ "kind": "home-rule", "ruleKind": "toggle-on-press", "path": "./dist/index.js", "export": "TogglePress" }
```

```ts
// @evok-node/driver-home
interface RuleKind<T extends Slots, A extends Slots, O> {
  readonly kind: string;               // must equal the manifest's ruleKind
  readonly label: LocalizedText;       // 04 §7
  readonly hint?: LocalizedText;
  readonly triggers: T;                // §3, at least one slot
  readonly actions: A;                 // §3, at least one slot
  readonly options?: TypedCodec<O>;    // annotated (05a §3.1a) — §3; absent ⇒ no options
  readonly limit?: TriggerLimit;       // §5.4
  run(ctx: RuleContext<T, A, O>): Promise<void>;   // §4
}
```

A kind whose `kind` disagrees with its manifest entry, with no trigger slot or no action slot, or whose slots break §3, is a packaging mistake — rejected when the kind is resolved.

### 2.1. Built-in kinds

Only `toggle-on-press` and `on-and-set-delay-off` have options. The `buttons` slots set `fields: ['switch']` (§3), so a change of a switch's `features` never runs them.

| Kind | Triggers | Actions | Does |
|---|---|---|---|
| `toggle-on-press` | `buttons`: `GenericSwitch`, 1–n | `lights`: `OnOffLight`, `DimmableLight`, `ColorTemperatureLight`, `ExtendedColorLight`, 1–n | The press chosen by `event` (below): if any light is on, all go off; otherwise all go on. |
| `dimmer-on-longpress` | `buttons`: `GenericSwitch`, 1–n | `lights`: `DimmableLight`, `ColorTemperatureLight`, `ExtendedColorLight`, 1–n | `longPress` → `move` in the current direction; `longRelease` → `stop`. The direction toggles on every long press. |
| `one-button-window-cover` | `buttons`: `GenericSwitch`, 1–n | `covers`: `WindowCovering`, 1–n | `shortRelease` → `up` or `down`, the end in the current direction. `longPress` → the same; `longRelease` → `stop`. The direction toggles on every press. |
| `on-and-set-delay-off` | `buttons`: `GenericSwitch`, 1–n | `lights`: `OnOffLight`, `DimmableLight`, `ColorTemperatureLight`, `ExtendedColorLight`, 1–n · `timer`: `TimerRelay`, 1 | The press chosen by `event`: all lights on, and `method` (below) on the timer. With `method: 'toggle'` and the timer running (12c-05 §1.1): all lights off, then `toggle` — the timer goes `idle` without `elapsed`, so `delay-off` never sees it. |
| `delay-off` | `timer`: `TimerRelay`, 1–n | `lights`: `OnOffLight`, `DimmableLight`, `ColorTemperatureLight`, `ExtendedColorLight`, 1–n | `elapsed` → all lights off. The slot sets `fields: ['elapsed']`. |

`toggle-on-press` options:

```ts
Codecs.struct({
  event:   Codecs.string({ enumValues: ['shortRelease', 'initialPress', 'multiPressComplete'], default: 'shortRelease',
             label: { en: 'Toggle on', cs: 'Přepnout při' } }),
  presses: Codecs.uint8({ min: 1, default: 1, label: { en: 'Presses', cs: 'Počet stisků' } }),   // multiPressComplete only: toggles when `count` equals it
})
```

| `event` | Fires | Trade-off (12c-03 §1.1) |
|---|---|---|
| `shortRelease` | on each short press's release | also on each press of a double |
| `initialPress` | on each press, at once | also on the first press of a long press |
| `multiPressComplete` | after exactly `presses` presses | late by the button's multi-press window; needs multi-press on |

A button that doesn't produce the chosen event — no multi-press, or no release (12c-03 §2) — never runs the rule.

The direction lives in the rule's state (§5.5). With no state yet, it points to the end farther from the current `level` or `position.current`. A button with short-press toggle and long-press dimming is two rules on the same button: `toggle-on-press` and `dimmer-on-longpress`.

`on-and-set-delay-off` options — `event` and `presses` as `toggle-on-press`, plus the timer call:

```ts
Codecs.struct({
  event:   …,   // as toggle-on-press
  presses: …,   // as toggle-on-press
  method:  Codecs.string({ enumValues: ['start', 'restart', 'add', 'toggle'], default: 'restart',
             label: { en: 'When running', cs: 'Když běží' } }),   // 12c-05 §1.1
})
```

The delay is the timer's own `defaultMs` (12c-05 §3): one timer, one delay, whichever rules start it.

## 3. Slots and options

```ts
// @evok-node/driver-home
interface Slot extends Selection {              // 12a §2.4: types, min, max, label, hint
  readonly fields?: readonly string[] | '*';    // trigger slots only — the engine's, never in the form
}
type Slots = Readonly<Record<string, Slot>>;    // slot key → slot
```

- `fields` says which field changes trigger a run. Omitted: every field the slot's types declare beyond `CommonFields` (12a §2.1), so renaming a switch never triggers anything. `'*'`: every field, `reachable` included. A named field missing from any of the slot's `types`, or `fields` on an action slot, is a packaging mistake.
- A device appears at most once per slot. It may be in a trigger slot and an action slot of the same rule at once.
- Options are one annotated codec (05a §3.1a). A **device option** is a member holding a `home.device` ref (12a §2.4) — one id, or an array of them. Its devices never trigger a run and are read-only in the function; they may also sit in a slot.
- The kind's form (12a §2.4) is built from `triggers`, `actions` and `options`; that is what a UI renders and what `createRule` is checked against.
- A slot or device option may allow several types. Telling them apart is the function's job, by `kind` (§4).

```ts
options: Codecs.struct({
  seconds:   Codecs.uint16({ min: 10, max: 3600, unit: 's', default: 120, label: { en: 'Stays on', cs: 'Svítí' } }),
  luxSensor: Codecs.optional(Codecs.string({ label: { en: 'Only when dark', cs: 'Jen za tmy' },
               ref: { type: 'home.device', filter: { kinds: ['home.LightSensor'] } } })),   // a device option
}),
```

## 4. Run context

```ts
// @evok-node/driver-home
interface RuleEvent {
  readonly slot: string;
  readonly tail: string;             // the device's own tail (12a §4.1)
  readonly kind: string;             // its DeviceType.kind
  readonly field: string;
  readonly value: Value;
  readonly at: Date;
}

interface DeviceSnapshot<D extends DeviceType> {
  readonly tail: string;
  readonly kind: D['kind'];
  readonly reachable: boolean;
  readonly values: Partial<ValuesOf<D>>;   // last known values; a field with no value yet is absent
}

interface ActionDevice<D extends DeviceType> extends DeviceSnapshot<D> {
  set<K extends ChannelKey<D>>(field: K, value: ValueOf<D, K>): void;    // fire and forget
  call<K extends MethodKey<D>>(method: K, args: ArgsOf<D, K>): void;     // fire and forget
}

interface RuleContext<T extends Slots, A extends Slots, O> {
  readonly event: RuleEvent;
  readonly rule: RuleRecord;                                                    // §6
  readonly triggers: { readonly [K in keyof T]: readonly SnapshotOf<T[K]>[] };
  readonly actions:  { readonly [K in keyof A]: readonly ActionOf<A[K]>[] };
  readonly options:  OptionValues<O>;       // a device option ⇒ its snapshot(s)
  state: Value | undefined;                 // §5.5; undefined until the first save
  readonly log: Logger;                     // 04 §3, scoped to this rule
}
```

`SnapshotOf`/`ActionOf` are unions over the slot's `types`, discriminated by `kind`:

```ts
for (const l of ctx.actions.lights) {
  if (l.kind === DimmableLight.kind) l.set('level', 254);   // narrowed: `level` exists
  l.set('onOff', true);
}
```

**Snapshots.** Every device in the context — trigger, action and device option — is a snapshot of the last known values, taken when the run starts. For a run that didn't wait in the queue (§5.1), that is the moment it was triggered. Values are frozen (basics/02-Coding §1.4), so a snapshot collects references and never copies values.

**Writes are fire and forget.** Reads are local and so are writes: the devices are this driver's own, so no messaging is involved.

- `set`/`call` check the payload against the field's codec at once. A bad payload throws, and the run errors (§5.3).
- They are then dispatched through the device's own handler — the same path an external `SET` takes: validation, forwarding to the source, emit — in call order, and never awaited.
- Their outcome (`unreachable`, `bad-payload`, …) is logged and kept as `lastActionError` (§8). It never fails the run.
- A write to a device that is also in a trigger slot triggers a new run when its change arrives, queued behind this one (§5.1).

## 5. Execution

### 5.1. Queue

- One run at a time per rule. A trigger arriving during a run waits in the rule's queue.
- The rules of one RuleSet (§6) share one queue: one run at a time across the set, first in, first out.
- A queue holds up to 16 triggers. On overflow the oldest is dropped and logged.
- A rule that is `disabled` or `device-removed` (§7) queues nothing.

### 5.2. Deadline

`run` has 100 ms (04 §6). Writes are never awaited, so the time is the function's own. Past the deadline the run counts as an error (§5.3), and its action handles go inert: a later write is dropped and logged.

### 5.3. Errors

A throw or a missed deadline is caught, logged, and kept as `lastError` (§8). The run's state is discarded: the next run gets the last saved state. Writes already dispatched stay — there is no rollback.

### 5.4. Trigger limit

```ts
interface TriggerLimit { readonly runs: number; readonly perMs: number }
```

The kind's `limit`, overridden by `RuleRecord.limit`; `{ runs: 10, perMs: 1000 }` when neither sets one. A trigger over the limit is dropped and logged, and the rule is `throttled` (§7). This is the only help against loops — loops and conflicts between rules are the user's.

### 5.5. State

- Opaque to the engine. JSON-shaped — the same data model as `Config` (02 §4); a state that doesn't encode is an error (§5.3).
- After a successful run, the encoded state is compared with the last saved one. Only if it differs is it written to KV, before the next run starts. It stays in memory between runs.
- `updateRule` keeps it. A kind treats a state it doesn't recognise as absent — that also covers a plugin upgrade.
- Removed with its rule.

### 5.6. Gaps and startup

- Subscriptions may coalesce (03 §6.3): a run may see a later value without the ones between. The function must tolerate it; `switch.lastEvent.seq` shows the gap (12c-03 §2).
- The first value a subscription delivers is the baseline, never a trigger — so a restart triggers nothing.
- A persistent `TimerRelay` resumes its countdown only after the engine has taken its baselines, so its expiry triggers even when little time was left (12c-05 §3).

## 6. Storage

```ts
// @evok-node/driver-home
interface RuleRecord {
  readonly id: string;                                              // generated, see below
  readonly ruleKind: string;
  readonly name: string;
  readonly enabled: boolean;
  readonly ruleSetId?: string;
  readonly triggers: Readonly<Record<string, readonly string[]>>;   // slot key → device tails
  readonly actions:  Readonly<Record<string, readonly string[]>>;
  readonly options:  Readonly<Record<string, Value>>;               // the form's `options`, defaults filled
  readonly limit?: TriggerLimit;                                    // §5.4
}

interface RuleSetRecord {
  readonly id: string;                                              // generated
  readonly name: string;
}
```

- `id` is generated by this driver when the record is created (`crypto.randomUUID()`). It is opaque: it keys the record in KV and in management calls (§8). A user only ever sees `name`.
- Each record, and each rule's state (§5.5), is its own key in this driver's KV namespace (06).
- A rule refers to devices by tail only. It is a weak entity: it never blocks a device's removal (§7).
- Removing a RuleSet clears `ruleSetId` on its rules, in one `batch` (06) with the removal.

## 7. Status

Computed, never stored:

| `status` | When | Runs | Cleared by |
|---|---|---|---|
| `device-removed` | a tail in a slot or a device option has no device record | no | the user, through `updateRule` |
| `disabled` | `enabled: false` | no | the user, through `updateRule` |
| `errored` | the last run failed (§5.3), or a device it uses is `missing` (12a §4.3) | yes | the next successful run, the device returning |
| `errored` | its kind doesn't resolve, or its stored options fail the kind's form | no | the kind returning, or the user fixing the options |
| `throttled` | the trigger limit dropped a trigger (§5.4) | yes | one limit window without a drop |
| `ok` | none of the above | yes | — |

The first row that holds wins.

## 8. Management endpoints

Same conventions as 12a §5: validate before anything is persisted, answer `domain-error`. The methods are fields of the same `manage` device, one args struct each (12a §5). Reachable from the Inspector UI and from the Home API (12a §5). The Home UI lists `controllable: false` devices for rules (12a §2.1).

```ts
type RuleStatus = 'ok' | 'errored' | 'throttled' | 'disabled' | 'device-removed';   // §7

listRuleKinds(): readonly {
  kind: string; label: LocalizedText; hint?: LocalizedText;
  form: ValueSchema;                     // 12a §2.4 — { triggers, actions, options }; format `schema` on the wire
  limit: TriggerLimit;                   // the effective default
}[];
createRule(args: {
  ruleKind: string; name: string;
  triggers: Record<string, readonly string[]>;   // the form's `triggers`
  actions:  Record<string, readonly string[]>;   // the form's `actions`
  options?: Record<string, Value>;       // the form's `options`; omitted ⇒ every default
  enabled?: boolean;                     // omitted ⇒ true
  ruleSetId?: string;
  limit?: TriggerLimit;
}): RuleRecord;
updateRule(args: { id: string; patch: {
  name?: string; enabled?: boolean; ruleSetId?: string | null;
  triggers?: Record<string, readonly string[]>; actions?: Record<string, readonly string[]>;
  options?: Record<string, Value>; limit?: TriggerLimit | null;
} }): RuleRecord;                        // ruleKind never changes
removeRule(args: { id: string }): void;
listRules(): readonly (RuleRecord & {
  status: RuleStatus; lastError?: string; lastActionError?: string; lastRunAt?: Date;
})[];

createRuleSet(args: { name: string }): RuleSetRecord;
updateRuleSet(args: { id: string; patch: { name?: string } }): RuleSetRecord;
removeRuleSet(args: { id: string }): void;         // its rules stay, without a set
listRuleSets(): readonly RuleSetRecord[];
```

`errorKinds`:

- `unknown-rule-kind`, `unknown-rule`, `unknown-rule-set`.
- `invalid-slots` — an unknown or missing slot, a device count outside `min`–`max`, a tail with no device record, a device whose kind isn't in the slot's `types`, a device twice in one slot.
- `invalid-options` — `options` fail the kind's form; for a device option, the same checks as `invalid-slots`.

Both are found by decoding the form and running `checkRefs` (05a §3.10).

## 9. Testing

Tier 1, against fixture home devices and a fake `Clock`:

- `listRuleKinds` answers one `form` per kind: a `home.device` ref array per slot, kinds taken from `types`, plus `options`; a slot's `fields` are not in it. `createRule` omitting an option with a default stores the default; a device option naming a device of another kind answers `invalid-options`.

- A trigger during a run waits and runs after it; two rules of one RuleSet never run at once; the 17th queued trigger drops the oldest.
- `fields` omitted: a `name` change never triggers, a `switch` change does; `'*'` triggers on `reachable` too.
- A run that throws, or overruns 100 ms, leaves the saved state unchanged; a write made after the deadline is dropped.
- State is written to KV only when its encoded form changed; after a restart the next run gets the saved state.
- `set` with a bad payload throws inside the run; a `set` to an unreachable device is logged as `lastActionError` and the run still succeeds.
- Over the trigger limit: triggers drop and the rule is `throttled`, back to `ok` after a window without drops.
- Removing a device used by a rule succeeds, and the rule becomes `device-removed` and stops running; a `missing` device makes it `errored` until it returns.
- Removing a RuleSet leaves its rules without a set.
- `createRule` with a wrong slot count, a device of the wrong kind, or an unknown tail answers `invalid-slots` before anything is written.
- Built-in kinds: `toggle-on-press` turns all lights off when one is on, and with `event: 'multiPressComplete', presses: 2` toggles on a double press only; `dimmer-on-longpress` sends `move` then `stop` and alternates direction; `one-button-window-cover` goes to the opposite end on each short press and stops on `longRelease`; `on-and-set-delay-off` switches the lights on and calls its `method`, and with `toggle` on a running timer switches them off instead; `delay-off` switches the lights off on `elapsed` only, never on `toggle` or `cancel`.
