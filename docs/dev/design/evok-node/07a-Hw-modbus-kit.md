# 07a — Hw-modbus-kit

## 1. Scope

The shared binder 08 and 09 both call: turns a `hw-definitions`-resolved definition into bound `driver-kit` devices, over this same package's own `ModbusTransport`, without either onboard or extension driver touching register arithmetic or `bindDevice` directly. It lives inside `packages/modbus` — the `hw-modbus-kit` subpath of what 01 §11 calls `modbus-kit` — not a separate npm package; §9 states what that costs and buys.

For the common case — every per-channel Unipi kind (`unipi.di`, `unipi.do`, `unipi.ro`, `unipi.led`, `unipi.ai`, `unipi.ao`) and every plain sensor kind (`unipi.temp`, `unipi.humidity`, …) — this file needs zero kind-specific code: a single schema-walking algorithm (§5) binds any `reading`/`channel`-shaped `DeviceType` from its own `ValueSchema` plus the YAML's own field addresses. The registry (§7) is for what that walk genuinely cannot do, and it's never about building a new `DeviceType` — every `DeviceType` this file ever binds against already exists and is independently resolvable (05a §3.5); a registered binder only ever supplies *how* to talk to one. Two distinct reasons a `kind` needs one: `unipi.sectionWatchdog`'s `saveConfig`/`reset` are `method`-shaped, and a `CALL` isn't a value with an address, so the real `unipi.sectionWatchdog` `DeviceType` needs its own `bind()` instead of the generic walk; or a YAML `kind` is a stand-in for a different, already-real kind entirely — a device with a register layout the generic walk can't express, bound as an ordinary `unipi.di` underneath once its own binder translates for it. Both are the worked examples in §7.

## 2. The kind↔`DeviceType` boundary

`hw-definitions` (07's sibling package) parses, structurally validates, and resolves addresses; it never resolves a `kind` string against a real `DeviceType` — it has no `ctx`, and no legitimate reason to want one. Everything it hands this file is data: a `ResolvedDefinition` whose `features[].kind` is still just a string.

This file is where that string becomes a bound device. `bindDefinition()` (§9) looks up `kind` against the registry (§7) first — a local `registerKind()` table, then, if absent there, `resolveKindBinder(kind)` (§7, §12) against the ambient manifest. If a binder is found, its `targetKind` (defaulting to `kind` itself) is what actually gets resolved to a real `DeviceType`, via `resolveDeviceKind` (05a §3.5); if no binder is found at all, `kind` itself is resolved the same way, and the device is built generically (§5) from whatever `ValueSchema` that `DeviceType` carries. Either path ends at the same `resolveDeviceKind` call, so a `kind` — or a binder's `targetKind` — that this file can't resolve fails exactly where an ordinary driver-authoring mistake already fails (05a §3.5), not somewhere new.

## 3. The YAML↔schema contract

Four rules this file assumes hold on every `hw-definitions` feature it's handed, none of them new: they're existing 05a mechanics plus this file's own scan cache, reused rather than reinvented on the YAML side of the boundary.

**A feature's field keys mirror the registered `EndpointType`'s own schema path.** This is 05a §5's facet grammar (`<tail>:value.duty`) again, just used to key a YAML `fields` map instead of a wire address — `pwm: { value: { duty, prescaler, cycle } }` in YAML because `DOValue`'s `pwm` variant is `struct({ value: PwmValue })` in the registered `EndpointType`. A mismatch here — YAML nesting that doesn't line up with the schema — is exactly what `validateAgainstManifest` (`hw-definitions`, checked before this file ever runs) exists to catch.

**A union's discriminant option names its own `variant`.** Never positional, never code-ordered:

```yaml
mode:
  holdingReg: { addr: 10, encoding: uint16 }
  options:
    - { code: 0, variant: voltage10,  unit: V,  range: [0, 10] }
    - { code: 1, variant: voltage2_5, unit: V,  range: [0, 2.5] }
    - { code: 2, variant: current20,  unit: mA, range: [4, 20], channels: [3, 4] }
```
`schema.tag` (`'mode'`, known from the registered `EndpointType`) plus `options[].variant` (known from the YAML) is what lets §5 go `code ↔ variant` for any union, with no per-kind lookup table.

**An address names its own register space explicitly.** `holdingReg` / `inputReg` / `coil` / `discreteInput` — never a generic `reg`/`coil` pair. Modbus has four independent address spaces, and the space alone decides writability: there is no function code that writes an input register or a discrete input. So a `channel`'s value may declare `holdingReg` and/or `coil` only; `inputReg`/`discreteInput` on a writable field is a load-time structural error (`validateAgainstManifest`), not something discovered on the first `SET`. Every Unipi map in the corpus turns out to use only `holdingReg` and `coil` — DI's coil mirror is read-only by the `kind` itself (05 §2), not by wire space — but a third-party, bring-your-own definition (09) is free to use the other two.

When a value declares both `holdingReg` and `coil` (§5 has the worked resolution): `SET` always writes through `coil`, unconditionally — `writeSingleCoil` (FC5) is atomic per bit, where a bit-packed register write is read-modify-write and two concurrent single-channel writes clobber each other, exactly the bug class research/13 documents. `GET` follows whichever block (§6) actually has fresh cached data for that value — in practice almost always the register form, since AI/AO/counter values force a holding-register block to exist anyway and slicing one more bit out of an already-scanned word costs nothing.

**A struct member named `polled` is never in the YAML.** It's a single reserved field, synthesized as a whole `{readAt: Date, stale: boolean}` unit by the scan cache (§6), for any `reading`-shaped endpoint bound through this file — every one of them, not a kind-by-kind choice, since every reading here is scan-cache-backed by construction. It is never legal on a `channel`'s `schema` or `setSchema`: `SET` always echoes exactly `TSet` (05a §3.1), and `readAt`/`stale` mean nothing on a value the caller just supplied. A `polled` member on a channel is a `bindDevice()`-time fatal, same tier as a duplicate tail (05a §3.5). §4 has the helper that makes this the default rather than something each kind re-derives by hand.

One consequence worth stating on its own: **there is no `perSection` attribute.** A register shared across every channel of a feature — a section-wide PWM prescaler/cycle, say — is never a sibling field of that per-channel feature. It's its own `kind`, bound with `count: 1` instead of `count: 4`. `unipi.pwmOpt` (§10) is the concrete, already-settled example:

```yaml
- kind: unipi.do
  count: 4
  value:  { coil: { addr: 1 }, holdingReg: { addr: 1, encoding: bool, bitOffset: 0 } }
  mode:   { holdingReg: { addr: 2, encoding: uint16 }, options: [{ code: 0, variant: bool }, { code: 1, variant: pwm }] }
  pwm:
    value: { holdingReg: { addr: 30, encoding: uint16 } }        # duty only — per-channel, stays on unipi.do

- kind: unipi.pwmOpt
  count: 1                                                        # one per section — an ordinary count, not a new attribute
  prescaler: { holdingReg: { addr: 1017, encoding: uint16 } }
  cycle:     { holdingReg: { addr: 1018, encoding: uint16 } }
```
`DOValue`'s `pwm` variant is correspondingly just `struct({ value: Codecs.uint16() })` — no `prescaler`/`cycle` inside it at all.

## 4. `polled()` — the reading helper

```ts
// @evok-node/modbus — hw-modbus-kit
function polled<F extends Record<string, TypedCodec<unknown>>>(
  kind: string, fields: F, opts?: { subscribe?: boolean }
): ReadingType<{ [K in keyof F]: Infer<F[K]> } & { polled: { readAt: Date; stale: boolean } }> {
  return reading(kind, Codecs.struct({ ...fields, polled: Codecs.struct({ readAt: Codecs.timestamp(), stale: Codecs.bool() }) }), opts);
}
```

Every `reading`-shaped kind in the catalogue (§10) is built with this, never a bare `reading()` call — that's what makes §3's `polled` rule a fact about this file rather than a convention someone has to remember per kind. `unipi.di`'s `@` field: `polled('unipi.di', { value: Codecs.bool(), counter: Codecs.uint32() }, { subscribe: true })`, decoding to `{ value: true, counter: 42, polled: { readAt: ..., stale: false } }`.

A driver not built on this file's scan cache — an event-native one, per 05 §4 — has no reason to use `polled()`; it stays module-sdk's plain `reading()`, and 05 §2's "the driver's own discretion" framing is exactly for that case. Inside `hw-modbus-kit`, there is no discretion: every reading is scan-cache-backed, so every reading uses `polled()`.

## 5. Wire value → Device value: four stages

Same pipeline on the way in (`GET`) and the way out (`SET`), and it's what every leaf of §6's `decodeValue`/`encodeValue` actually does, spelled out once here rather than hand-waved as "decodeWord + scale":

```
Modbus wire (number[] | bool[] | bool | number)
  → YAML `encoding`   (word order, bit position, signedness, width)      → number | bigint | bool
  → YAML `scale`      (composes with the schema's own Semantics.scaler, never replaces it)
  → Device `Codec<T>` (validate() + its own declared Semantics.scaler)   → T
```

**Stage 1 → 2, `encoding`.** Owned by `hw-definitions`. Decides how many registers/bits a value spans and how to turn raw wire content into one typed primitive — `uint16`/`int16`/`uint32` (word-swapped, CDAB)/`float32` (word-swapped)/`bool`+`bitOffset`. **`encoding.format` must equal the resolved schema leaf's own `ValueSchema.format`, identically** — not merely "produces a same-shaped JS value." A `uint16` YAML encoding against a schema leaf declared `format: 'timestamp'` is nonsense even though both happen to be numbers; `validateAgainstManifest` rejects it before this file ever runs.

**Stage 2 → 3, `scale`.** Also `hw-definitions`, applied right after decoding, still before anything reaches a `Codec`. `scale` and the schema's own `Semantics.scaler` (05a §3.1) are not alternatives — they compose. The YAML author sets `scale` accounting for whatever `scaler` the registered `EndpointType` already declares, so the total conversion factor is deliberate, not an accidental double-scale. There's no mechanical check for "the right total factor" — only review, same as `provenance` review elsewhere (research/13 §5.1).

**Stage 3 → 4, the Device `Codec<T>`.** Whatever `hw-definitions` produced is what the registered `Codec<T>` treats as its own wire value — `validate()`, then its own `decode()`, including its own `scaler` if one is declared.

## 6. The generic bind algorithm

Everything below is Modbus-aware only where it touches `Encoding`/`decodeWord` (`hw-definitions`, §5's stages 1–2) or issues a wire call; the struct/union walk itself operates purely on `ValueSchema` and would be identical for a future transport that isn't Modbus at all.

```ts
// @evok-node/modbus — hw-modbus-kit
function decodeValue(schema: ValueSchema, node: YamlFieldNode, ctx: WireBindCtx): unknown {
  switch (schema.type) {
    case 'primitive':
      return ctx.cache.get(node as ResolvedAddress);          // §5's stages 1–3, then the Codec (stage 4) is applied by the caller
    case 'struct':
      return Object.fromEntries(Object.entries(schema.fields).map(([k, sub]) =>
        k === 'polled'
          ? [k, ctx.cache.polledStatus((node.value ?? node).blockId)]   // one call, {readAt, stale} together — §4
          : [k, decodeValue(sub, node[k], ctx)]));
    case 'union': {
      const code = ctx.cache.get(node.mode.holdingReg ?? node.mode.coil!);
      const opt = node.mode.options.find((o: ModeOption) => o.code === code)!;
      return { [schema.tag]: opt.variant, ...decodeValue(schema.variants[opt.variant], node.variants?.[opt.variant] ?? node, ctx) };
    }
    case 'array': throw new Error('array-shaped features are not part of the built-in catalog yet');
  }
}

function encodeValue(schema: ValueSchema, node: YamlFieldNode, value: unknown, ctx: WireBindCtx): Promise<void> {
  // mirrors decodeValue, collecting { address, value } writes bottom-up rather than reading them, then:
  //  - a bool leaf writes through `coil` when the node has one, `holdingReg` otherwise — never the reverse,
  //    even when both exist (§3's write-preference rule; FC5's atomicity is why);
  //  - a struct's leaf writes, if every one is register-backed and contiguous (asserted by hw-definitions'
  //    own validate() via `stride`, never re-checked here), batch into one writeMultipleRegisters —
  //    this is what makes the DO pwm triple "computed together" without either side knowing it's PWM;
  //  - a mismatched mode write (schema.tag's value naming a variant this feature's options exclude for
  //    this channel) throws RejectedPayload (05a §3.5) before any write reaches the wire.
}
```

`ResolvedAddress` (`hw-definitions`) carries its own `blockId`, resolved once at load time from the declared `blocks:` ranges — that's what makes the `polled` case above a direct lookup rather than something threaded through `ctx`. `blockId` is never a property of `WireBindCtx` itself (§9); it travels on the resolved address.

A worked trace against §3's `unipi.do` feature, `onSet({ mode: 'pwm', value: { duty: 4000 } })`: `decodeValue`/`encodeValue` walk `DOValue`'s `union` arm, resolve `variant: pwm` to `code: 1`, write holding register 2 (`mode`) then register 30+`channelIndex` (`pwm.value`, one register — no batching needed, since `pwm.value` is now a bare `uint16`, not a struct, per §3's split). Against `unipi.ao`'s feature from the same board, `onSet({ mode: 'current20', value: 8000 })` on channel 0 (AO1): `decodeValue` finds `opt.channels = [3, 4]`, doesn't include `1` (1-based, matching the YAML), and `encodeValue` throws `RejectedPayload` before either register write.

## 7. The escape hatch — `ModbusKindBinder`

```ts
// @evok-node/modbus — hw-modbus-kit
interface ModbusKindBinder<F extends Record<string, EndpointType | OptionalEndpointType> = any> {
  readonly kind: string;          // matches ResolvedFeature.kind
  readonly targetKind?: string;   // the real, resolvable DeviceType.kind to bind against — defaults to `kind` itself
  bind(ctx: WireBindCtx, feature: ResolvedFeature, deviceType: DeviceType<F>): { [K in keyof F]?: BindHandlers<any, any, any> };
}
```

A binder never builds a `DeviceType` — the type itself always already exists and is independently resolvable (05a §3.5); a binder only ever supplies *how* to talk to one over the wire. `targetKind` is what makes that distinction concrete, and it covers two genuinely different reasons a `kind` needs a binder at all, both resolved to a real `DeviceType` (via `resolveDeviceKind`, §12) before `bind()` ever runs:

- **Same kind, custom bind.** `targetKind` omitted (defaults to `kind`). The walk itself can't handle this kind — not an aliasing problem. `unipi.sectionWatchdog` is the built-in example: its `saveConfig`/`reset` fields are `method`-shaped, and a `CALL` isn't a value with an address, so there's nothing for §6's schema-walker to walk.

  ```ts
  // @evok-node/modbus — hw-modbus-kit
  async function forceCoil(ctx: WireBindCtx, address: number): Promise<CallOutcome<void>> {
    const r = await ctx.tx.writeSingleCoil({ unitId: ctx.unitId, address, value: true });
    return r.ok ? { ok: true, result: undefined } : r;
  }

  const sectionWatchdogBinder: ModbusKindBinder<SectionWatchdogFields> = {
    kind: 'unipi.sectionWatchdog',              // targetKind omitted — SectionWatchdogDevice.kind is this same string
    bind: (ctx, feature, deviceType) => ({
      saveConfig: { onCall: () => forceCoil(ctx, feature.coils.saveConfig) },
      reset:      { onCall: () => forceCoil(ctx, feature.coils.reset) },
    }),
  };
  ```

  `SectionWatchdogDevice` is a same-package built-in — `hw-modbus-kit` imports it directly, so resolving `targetKind` here is trivially cheap (05a §3.5's direct-import path), never a `PluginRegistry` round-trip.

- **Alias — a different, already-real kind underneath.** `targetKind` names a kind genuinely different from `kind`. This is the shape a 09-style bring-your-own definition needs: a physical device with a register layout the generic walk can't express, whose channels are otherwise ordinary. A fictitious `acme.wm-relay` with a queer bit-packed coil layout, bound as nothing more exotic than `unipi.ro` underneath:

  ```ts
  const wmRelayBinder: ModbusKindBinder<RoFields> = {
    kind: 'acme.wm-relay',
    targetKind: 'unipi.ro',
    bind: (ctx, feature, deviceType) => ({
      '@': {
        onGet: () => readWmPackedCoil(ctx, feature),      // acme's own translation, not §6's generic walk
        onSet: (v) => writeWmPackedCoil(ctx, feature, v),
      },
    }),
  };
  ```

  Every client still sees an ordinary `unipi.ro` — `deviceType` here is the real, resolved `RoDevice`, identical to what any other `unipi.ro` binds against; only the wire translation inside `bind()` is acme's own.

Registered one of two ways, same duality as every other kind `PluginRegistry` owns (02 §4): **direct**, a build-time-known binder — `registerKind(binder)` (§12), what `unipi.sectionWatchdog` itself uses, called once at this package's own load; or **manifest**, a binder whose identity is only a string in someone else's config — a `kind: "modbus-kind-binder"` `package.json` entry, resolved lazily via `resolveKindBinder(kind)` (§12):

```json
// @acme/evok-node-wm3f — package.json
{
  "evokNodePlugin": {
    "manifestVersion": "1",
    "plugins": [
      { "kind": "modbus-kind-binder", "deviceKind": "acme.wm-relay", "path": "./dist/index.js", "export": "wmRelayBinder" }
    ]
  }
}
```

`deviceKind` — same field name a plain `device` entry uses, since both answer "what does this string resolve to," but a separate namespace (02 §4): `device` and `modbus-kind-binder` never collide on the same string, because a `ResolvedFeature.kind` is looked up against exactly one of them (§2), never both. `bindDefinition()` checks the local `registerKind()` table first, and only calls `resolveKindBinder` if nothing is found there — a plugin package pays the `PluginRegistry` round-trip once, memoized after (02 §4); a build-time-known binder, direct or third-party, never pays it at all.

Registering `isModbusKindBinder` itself as `'modbus-kind-binder'`'s own guard is this package's job, at its own module-load time — same tier as `driver-kit` registering `isDeviceType` for `'device'` (05a §3.5):

```ts
// @evok-node/modbus — hw-modbus-kit, module-load time, once
function isModbusKindBinder(mod: unknown, deviceKind: string): ModbusKindBinder {
  if (typeof mod !== 'object' || mod === null
      || typeof (mod as ModbusKindBinder).kind !== 'string'
      || typeof (mod as ModbusKindBinder).bind !== 'function') {
    throw new Error(`modbus-kind-binder "${deviceKind}": not a valid ModbusKindBinder`);
  }
  if ((mod as ModbusKindBinder).kind !== deviceKind) {
    throw new Error(`modbus-kind-binder "${deviceKind}": exported .kind is "${(mod as ModbusKindBinder).kind}"`);
  }
  return mod as ModbusKindBinder;
}
pluginRegistry.registerKindGuard('modbus-kind-binder', isModbusKindBinder);
```

Every other built-in kind (§10) resolves through the generic walk alone, no binder at all.

## 8. Scan cache and block-scan loop

Owned entirely by this file. `driver-kit` does not provide a generic scan/staleness primitive — see the note on `packages/driver-kit/README.md` and 05a §2, both amended alongside this file — so nothing here is layered on a lower-level helper; it's plain scheduling against this package's own `ModbusTransport`.

```ts
// @evok-node/modbus — hw-modbus-kit
interface ScanCache {
  get(addr: ResolvedAddress): number | boolean;                    // §5's stages 1–3 already applied
  polledStatus(blockId: string): { readAt: Date; stale: boolean };  // §4's `polled` field, one call
}

class DefaultScanCache implements ScanCache {
  private blocks = new Map<string, { words: readonly number[] | readonly boolean[]; at: Millis; failed: boolean }>();
  constructor(private defBlocks: readonly ResolvedBlock[], private clock: Clock) {}

  updateFromScan(block: ResolvedBlock, raw: readonly number[] | readonly boolean[]) {
    this.blocks.set(block.id, { words: raw, at: this.clock.now(), failed: false });
  }
  markScanFailed(blockId: string) {
    const b = this.blocks.get(blockId);
    if (b) b.failed = true;   // prior snapshot and its age stay exactly as they were
  }
  get(addr: ResolvedAddress): number | boolean { /* locate the owning block, decodeWord, applyScale — §5's stages 1–3 */ }
  polledStatus(blockId: string): { readAt: Date; stale: boolean } {
    const b = this.blocks.get(blockId);
    return { readAt: b ? new Date(b.at) : new Date(0), stale: !b || b.failed };
  }
}

function startScanLoop(tx: ModbusTransport, unitId: number, blocks: readonly ResolvedBlock[], cache: DefaultScanCache, rates: RateTable, scheduler: Scheduler): () => void {
  const stop = blocks.map(b => scheduler.every(rates[b.rate], async () => {
    const raw = b.type === 'coil' ? await tx.readCoils({ unitId, address: b.start, count: b.count })
                                   : await tx.readHoldingRegisters({ unitId, address: b.start, count: b.count });
    if (raw.ok) cache.updateFromScan(b, raw.result);
    else cache.markScanFailed(b.id);
    // the prior snapshot is never discarded on failure — only marked stale. Nothing is ever thrown out of
    // the scheduler itself, matching 03 §7's "never fails silently into a wrong value" extended to a
    // background loop that has no caller to answer directly.
  }));
  return () => stop.forEach(s => s());
}
```

`stale` is deliberately **not** "older than N seconds" — it's "the most recent scan attempt for this block failed, or none has ever succeeded." A block that scans successfully once and is then never touched again (a driver bug, say) reports `stale: false` forever; that's a gap to know about, not one this file closes.

## 9. Handshake

```ts
// @evok-node/modbus — hw-modbus-kit
interface HandshakeResult {
  ok: boolean;
  reason?: 'unreachable' | 'timeout' | 'hardware-id-mismatch' | 'census-mismatch' | 'firmware-below-floor';
  detail?: string;
  variant?: string;   // which firmware-variant file was selected (research/13 §2.2) — diagnostic only
}

type HandshakeFn = (tx: ModbusTransport, unitId: number, def: UnresolvedDefinition) => Promise<HandshakeResult>;
```

`handshake(def)` (§12) looks up `def.handshake` — a name, defaulting to `'unipi.handshake'` when the YAML key is absent, which is every definition in the shipped catalog today; no existing definition needs editing — and dispatches to whichever `HandshakeFn` is registered under that name. The caller-facing contract, `handshake(def): Promise<HandshakeResult>`, doesn't change regardless of which `HandshakeFn` actually runs: `08`/`09` still call it exactly once, before `bindDefinition()`, and still treat a non-`ok` result as their own cue to refuse the unit outright — "refusal to run, not a warning," per research/13 §2.1 — never something this file downgrades to a log line. So `08 §5` needs no edit for any of this.

**`'unipi.handshake'`** is the built-in, registered directly at this package's own load — the algorithm this section always described: runs the identity check (research/13 §2.1 — `hardwareId` where known, `census` otherwise) and firmware-variant selection (§2.2) against a live unit, reading the identification block (holding 1000–1009) directly, through raw transport calls, before anything is bound. Once `bindDefinition()` runs, `unipi.info` (§10) exposes the same registers to ordinary clients through the generic scan-cache path — two different read paths over the same physical registers, never in conflict, since a `HandshakeFn` never runs again after bind.

**`handshake: none`** short-circuits to `{ok: true}` before any wire call at all — no identity check, no firmware-variant selection, neither partially. For a bring-your-own definition with no known identity block (09 §7), this is the honest choice over pretending census-checking degrades gracefully; a definition that wants partial checking registers its own `HandshakeFn` instead and does exactly as much as it chooses to inside it.

**A third-party `HandshakeFn`** registers the same two ways every other pluggable kind in this file does (§7, 02 §4): direct, `registerHandshake(name, fn)` (§12), for one known at build time; or manifest, a `kind: "modbus-handshake"` `package.json` entry (`handshakeName` the identifying field), resolved lazily via `resolveHandshake(name)` (§12). `handshake(def)` checks the local `registerHandshake()` table first, falling back to `resolveHandshake` only if nothing is found there — same order §7's binder lookup already follows. An unregistered name — not found locally, and not resolvable through the manifest either — is fatal before any wire traffic, the same tier as an unresolvable `kind` (§2).

Registering `isHandshakeFn` as `'modbus-handshake'`'s own guard, at this package's own load, mirrors `'modbus-kind-binder'`'s (§7) exactly, just checking `typeof mod === 'function'` in place of a shape object — a bare function has no fields to duck-type against.

## 10. The built-in kind catalogue

All `unipi.`-prefixed. Every `reading`-shaped field below is built with `polled()` (§4) even where the table just says "reading" for brevity — the `polled` member is implied, never re-listed per field. A device with no `@` is a sibling-only bundle (05a §3.3 permits this — 07's own `MODBUS_RAW` is the existing example) — there is no single primary signal to root the tail on.

### 10.1 Per-channel I/O

| Kind | Fields | Notes |
|---|---|---|
| `unipi.di` | `@`: reading `{value: bool, counter: uint32}`, subscribe · `debounce`: channel\<uint16, ms\> · `directSwitch`: optional channel `{enable: bool, polarity: bool, toggle: bool}` | |
| `unipi.do` | `@`: channel, union `mode ∈ {bool: {value: bool}, pwm: {value: uint16}}`, subscribe | duty only; `prescaler`/`cycle` live on `unipi.pwmOpt` |
| `unipi.ro` | `@`: channel\<bool\>, subscribe | |
| `unipi.led` | `@`: channel\<bool\>, subscribe | covers ULED, including Edge's unit-0 instance |
| `unipi.ai` | `@`: reading `{value: union('mode', {off, voltage10, voltage2_5, current20, resistance3w, resistance2w})}`, subscribe | per-option `channels` restriction (Edge); `conversionTime` hint on a resistance option |
| `unipi.ao` | `@`: channel, union `mode ∈ {voltage10, voltage2_5, current20, resistance}` | section-1 AOR (resistance-measure) is just the `resistance` option — no separate kind |

### 10.2 Section-wide, `count: 1`, no channel index in the tail

| Kind | Fields | Registers |
|---|---|---|
| `unipi.sectionWatchdog` | `enabled`: channel\<bool\> · `rebootDetected`: reading\<bool\>, subscribe · `timeoutMs`: channel\<uint16\> · `saveConfig`: method (mutates, void, via §7) · `reset`: method (mutates, void, via §7) | holding 0 bit0/bit1, holding 1008, coil 1003, coil 1002 |
| `unipi.pwmOpt` | `prescaler`: channel\<uint16\> · `cycle`: channel\<uint16\> | holding 1017/1018 |
| `unipi.info` | `firmwareVersion`/`firmwareId`/`hardwareId`: reading\<uint16\> · `serial`: reading\<uint32\> · `vref`: reading\<uint16\> | holding 1000/1003/1004/1005-6/1009 — diagnostic; never re-checked after `handshake()` (§9) |
| `unipi.storage` | `eraseCyclesPct`/`goodBlocksPct`: reading\<uint16\> · `powerCycles`: optional reading\<uint16\> · `vendor1`/`vendor2`/`vendor3`: optional reading\<uint16\> | holding 4000–4005, unit-0 only, whole controller not per section; absent on Unipi 1.1 |
| `unipi.lteConn` | `mode`/`networkType`: reading\<uint16\>, raw — enum undocumented anywhere in the corpus, including the LTE-capable Edge model · `rssiDbm`: reading\<int16\> · `signalQuality`: reading\<uint16\> | holding 4200–4203, Edge unit-0 only |

### 10.3 Sensor / accessory — single-`@`, no siblings unless noted

| Kind | Fields | Used by |
|---|---|---|
| `unipi.temp` | `@`: reading\<float32, °C\>, subscribe · `valid`: optional reading\<bool\> · `intervalS`: optional channel\<uint16\> | IAQ (bare) and xG18 (`valid` + `intervalS` bound, 8 instances) — one shared kind; the `int16×0.01` vs `float32` wire difference is a §5 `encoding`/`scale` concern, not a schema concern |
| `unipi.humidity` / `unipi.dewPoint` / `unipi.absHumidity` / `unipi.co2` / `unipi.vocIndex` / `unipi.vocAccuracy` / `unipi.vocCo2Eq` / `unipi.lux` / `unipi.pressure` / `unipi.uptime` | `@`: reading\<float32\>, subscribe | IAQ only. `co2`/`vocIndex`/`vocAccuracy`/`vocCo2Eq` bound only on the `THC` variant — which fields split per variant is still open (research, not this file) |
| `unipi.ledLevel` | `@`: channel\<uint16, 1–100%\> | IAQ's own status LED — distinct from `unipi.led` because the value type differs (level, not bool) |

IAQ's digital output reuses `unipi.ro` as-is — a plain bool channel, no new kind.

`unipi.ro` (EMO-R8's 8 relays) stays blocked: no register map exists yet anywhere (§11).

## 11. Placement: native code and process isolation

This file's home is `packages/modbus` — the same package as `ModbusTransport` and `MODBUS_RAW` (07) — not a package of its own. That's a deliberate widening of what was, until this file, a strictly wire-protocol-only boundary: `modbus` now depends on `driver-kit` and `hw-definitions`, where it previously depended on neither, and its own `README.md` is amended accordingly. The split stays visible in the source tree (`packages/modbus/src/hw-modbus-kit/`) even though the DAG can no longer enforce it as a package edge — `packages/modbus`'s own internal organization is what carries the boundary now, not `.dependency-cruiser.cjs`.

`driver-onboard` (08) and `driver-extension` (09) own transport lifecycle (`open`/`close`) and unit/line topology; each calls `handshake()` then `bindDefinition()` once per unit and never touches `driver-kit` or a register address directly. Their own DAG entry shrinks from `['messaging', 'driver-kit', 'modbus', 'hw-definitions']` to `['messaging', 'modbus', 'hw-definitions']` — `hw-definitions` stays a direct dependency for id/config resolution (naming which definition a `unit:` config key points at), even though every actual binding call now goes through `modbus`.

## 12. The complete interface

```ts
// @evok-node/modbus — hw-modbus-kit
type Millis = number;
type RateTable = Readonly<Record<string, Millis>>;   // named rates resolved by the owning driver's own config

interface WireBindCtx {
  readonly tx: ModbusTransport;
  readonly unitId: number;
  readonly cache: ScanCache;
}

interface BoundDefinition {
  readonly unitId: number;
  health(): ModbusHealth;      // re-exported verbatim from this same package's transport engine (07 §4) — no second breaker concept
  unbind(): void;               // tears down every device this call bound, stops its scan loop
}

interface HwModbusKit {
  registerKind(binder: ModbusKindBinder): void;                                   // §7 — direct, build-time-known; `unipi.sectionWatchdog` is built-in
  registerHandshake(name: string, fn: HandshakeFn): void;                         // §9 — direct; `'unipi.handshake'` is built-in
  resolveKindBinder(kind: string): Promise<ModbusKindBinder>;                     // §7 — manifest-declared, lazy: ctx.plugins.resolve('modbus-kind-binder', kind)
  resolveHandshake(name: string): Promise<HandshakeFn>;                           // §9 — manifest-declared, lazy: ctx.plugins.resolve('modbus-handshake', name)
  handshake(def: UnresolvedDefinition): Promise<HandshakeResult>;                  // §9 — always before bindDefinition; checks registerHandshake's table, then resolveHandshake
  bindDefinition(def: ResolvedDefinition, rates: RateTable): BoundDefinition;      // §6/§7/§8 combined — the one call 08 and 09 share
}

function createHwModbusKit(
  kit: DriverKit,
  tx: ModbusTransport,                       // one per owning driver instance — embedded, 07 §7
  deps: { clock: Clock; log: Logger; scheduler: Scheduler; plugins: PluginRegistry },   // `plugins` is `ctx.plugins` (03 §9) — what resolveKindBinder/resolveHandshake reach through
): HwModbusKit;
```

## 13. Testing

Tier 1, against a fixture `ResolvedDefinition` and the simulator (`design/simulator`) — no hardware:

- Schema-walk roundtrip: a struct with a nested struct field, and a union whose active variant is picked from a live `mode` register, both decode and encode correctly; a union facet path that doesn't match the current variant is never fabricated.
- `polled` synthesis: a `reading`-shaped fixture kind built with `polled()` never sees `polled` as a YAML key; a fixture `channel` (or `setSchema`) declaring a `polled` member is fatal at `bindDevice()` time, before `attach()`.
- Stale-after-failure: a block's first scan succeeds, then a later scan attempt fails — the next `onGet`'s `polled.stale` is `true`, while `polled.readAt` still reports the last *successful* snapshot's time, never the failed attempt's. This is the case §8's `stale = lastScanAt === null` design would have missed.
- Register-space validation: a fixture `channel` feature declaring `inputReg` or `discreteInput` is rejected at load time, naming the field.
- Encoding/schema match: a fixture feature whose `encoding.format` disagrees with its resolved schema leaf's `ValueSchema.format` is rejected at load time.
- Write-prefers-coil: a fixture value declaring both `holdingReg` and `coil` writes only through the coil on `SET`, asserted against the fixture transport's own call log — the register is never touched.
- Channel restriction: a mode `onSet` naming a variant excluded by that channel's own `options[].channels` answers `bad-payload` via `RejectedPayload`, never reaches the transport.
- Handshake dispatch: `handshake: none` never issues a wire call, asserted against the fixture transport's own call log, and skips firmware-variant selection along with identity; an unregistered `handshake` name is fatal before any wire traffic; a fixture manifest-declared `HandshakeFn` (`kind: "modbus-handshake"`) resolves and runs identically to a directly-`registerHandshake`d one.
- Kind-binder resolution: a fixture alias binder (`targetKind` naming a different, real fixture `DeviceType`) binds through to that real type correctly — introspection reports the real kind, not the alias; a binder whose `targetKind` resolves to a `DeviceType` whose own `.kind` disagrees is fatal, before any wire traffic; a fixture manifest-declared binder (`kind: "modbus-kind-binder"`) resolves and binds identically to a directly-`registerKind`d one.
- Contiguous-struct batching: a struct value backed by contiguous registers writes as exactly one `writeMultipleRegisters` call — never split into per-field writes.
- `unipi.pwmOpt` binds exactly once regardless of how many `unipi.do` channels the fixture definition declares.
- Handshake refusal: a `census` mismatch, a `hardwareId` mismatch, and a board below every variant's `minFirmware` floor each answer a non-`ok` `HandshakeResult` naming the right `reason`, and `bindDefinition()` is never reached in any of the three.
- The registry (§7): a fixture `kind` with no registered `ModbusKindBinder` and no manifest-resolvable `DeviceType` fails at `bindDefinition()`, naming the kind; `unipi.sectionWatchdog`'s registered binder is used in preference to the generic walk for its `saveConfig`/`reset` fields, which the generic walk never attempts.

## 14. Open

- **ForceOutput / the DirectSwitch write path.** No register named `ForceOutput` exists anywhere in the corpus; a `Synchronised DO/RO` + `Lock` register pair is the only candidate, and it's unverified on live hardware (research/06 §2.5). Not in the catalogue (§10) until confirmed.
- **RS485 config / Modbus-address registers.** Deliberately not modeled as a Device at all yet — floats per model with no fixed offset, and writing your own Modbus address at runtime is self-disconnecting. Revisit once there's a concrete need.
- **`unipi.ro` for EMO-R8.** No register map exists anywhere published for this extension. Blocked until one is sourced (EVOK's shipped `EMO-R8.yaml`, a different KB page, or measurement).
