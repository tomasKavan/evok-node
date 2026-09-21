# 07a — Hw-modbus-kit

## 1. Scope

The shared binder 08 and 09 both call: turns a `hw-definitions`-resolved definition into bound `driver-kit` devices, over this same package's own `ModbusTransport`, without either onboard or extension driver touching register arithmetic or `bindDevice` directly. It lives inside `packages/modbus` — the `hw-modbus-kit` subpath of what 01 §11 calls `modbus-kit` — not a separate npm package; §9 states what that costs and buys.

For the common case — every built-in Unipi kind (`DI`, `DO`, `RO`, `LED`, `AI`, `AO`, `WD`, `PWM_OPT`) — this file needs zero kind-specific code: a single schema-walking algorithm (§4) binds any `reading`/`channel`-shaped `DeviceType` from its own `ValueSchema` plus the YAML's own field addresses. A small registry (§6) exists only for what that walk genuinely cannot do — a `method`-shaped endpoint, or a hardware quirk too irregular to express as a schema path.

## 2. The kind↔`DeviceType` boundary

`hw-definitions` (07's sibling package) parses, structurally validates, and resolves addresses; it never resolves a `kind` string against a real `DeviceType` — it has no `ctx`, and no legitimate reason to want one. Everything it hands this file is data: a `ResolvedDefinition` whose `features[].kind` is still just a string.

This file is where that string becomes a bound device. `bindDefinition()` (§8) looks up `kind` against the registry (§6) if an entry exists there, and otherwise builds the device generically (§4) from whatever `DeviceType` the running instance's own manifest (05a §6.4, 02 §4) already has registered under that `kind` — the same manifest `driver-kit`'s `bindDevice()` checks against, so a `kind` this file can't resolve fails exactly where an ordinary driver-authoring mistake already fails, not somewhere new.

## 3. The YAML↔schema contract

Three rules this file assumes hold on every `hw-definitions` feature it's handed, none of them new: they're existing 05a mechanics, reused rather than reinvented on the YAML side of the boundary.

**A feature's field keys mirror the registered `EndpointType`'s own schema path.** This is 05a §5b's facet grammar (`<tail>:value.duty`) again, just used to key a YAML `fields` map instead of a wire address — `pwm: { value: { duty, prescaler, cycle } }` in YAML because `DOValue`'s `pwm` variant is `struct({ value: PwmValue })` in the registered `EndpointType`. A mismatch here — YAML nesting that doesn't line up with the schema — is exactly what `validateAgainstManifest` (`hw-definitions`, checked before this file ever runs) exists to catch.

**A union's discriminant option names its own `variant`.** Never positional, never code-ordered:

```yaml
mode:
  reg: { addr: 10, encoding: uint16 }
  options:
    - { code: 0, variant: voltage10,  unit: V,  range: [0, 10] }
    - { code: 1, variant: voltage2_5, unit: V,  range: [0, 2.5] }
    - { code: 2, variant: current20,  unit: mA, range: [4, 20], channels: [3, 4] }
```
`schema.tag` (`'mode'`, known from the registered `EndpointType`) plus `options[].variant` (known from the YAML) is what lets §4 go `code ↔ variant` for any union, with no per-kind lookup table.

**A struct member named `readAt` or `stale` is never in the YAML.** Both are synthesized by the scan cache (§5) from block metadata, for any `reading`-shaped endpoint — a fixed, kind-independent rule, not something a feature declares.

One consequence worth stating on its own: **there is no `perSection` attribute.** A register shared across every channel of a feature — a section-wide PWM prescaler/cycle, say — is never a sibling field of that per-channel feature. It's its own `kind`, bound with `count: 1` instead of `count: 4`. Cardinality was always just `count`; the earlier draft of this design only needed a second mechanism because it had wrongly nested the shared registers inside the per-channel one.

```yaml
- kind: DO
  count: 4
  value: { reg: { addr: 1, encoding: bool, bitOffset: 0 } }
  mode:  { reg: { addr: 2, encoding: uint16 }, options: [{ code: 0, variant: bool }, { code: 1, variant: pwm }] }
  pwm:
    value: { reg: { addr: 30, encoding: uint16 } }        # duty only — per-channel, stays on DO

- kind: PWM_OPT
  count: 1                                                 # one per section — an ordinary count, not a new attribute
  prescaler: { reg: { addr: 1017, encoding: uint16 } }
  cycle:     { reg: { addr: 1018, encoding: uint16 } }
```
This also happens to match the hardware better than the nested version would have: PWM frequency (`prescaler`/`cycle`) is a section-wide setting, changed rarely; duty is per-channel, changed often. `DOValue`'s `pwm` variant is correspondingly just `struct({ value: Codecs.uint16() })` — no `prescaler`/`cycle` inside it at all — and `PwmOptDevice` is an ordinary two-field `channel` device bound once, with no channel index in its tail.

## 4. The generic bind algorithm

Everything below is Modbus-aware only where it touches `Encoding`/`decodeWord` (`hw-definitions`) or issues a wire call; the struct/union walk itself operates purely on `ValueSchema` and would be identical for a future transport that isn't Modbus at all.

```ts
// @evok-node/modbus — hw-modbus-kit
function decodeValue(schema: ValueSchema, node: YamlFieldNode, ctx: WireBindCtx): unknown {
  switch (schema.type) {
    case 'primitive':
      if (schema.format === 'timestamp' && node === 'readAt') return ctx.cache.lastScanAt(ctx.blockId) ?? new Date(0);
      if (schema.format === 'bool'      && node === 'stale')  return ctx.cache.lastScanAt(ctx.blockId) === null;
      return ctx.cache.get(node as ResolvedAddress);                          // decodeWord + scale — hw-definitions, §5
    case 'struct':
      return Object.fromEntries(Object.entries(schema.fields).map(([k, sub]) => [k, decodeValue(sub, node[k], ctx)]));
    case 'union': {
      const code = ctx.cache.get(node.mode.reg ?? node.mode.coil!);
      const opt = node.mode.options.find((o: ModeOption) => o.code === code)!;
      return { [schema.tag]: opt.variant, ...decodeValue(schema.variants[opt.variant], node.variants?.[opt.variant] ?? node, ctx) };
    }
    case 'array': throw new Error('array-shaped features are not part of the built-in catalog yet');
  }
}

function encodeValue(schema: ValueSchema, node: YamlFieldNode, value: unknown, ctx: WireBindCtx): Promise<void> {
  // mirrors decodeValue, collecting { address, value } writes bottom-up rather than reading them, then:
  //  - a bool leaf writes through `coil` when the node has one, `reg` otherwise (research/13 §4.1 rule 2);
  //  - a struct's leaf writes, if every one is register-backed and contiguous (asserted by hw-definitions'
  //    own validate() via `stride`, never re-checked here), batch into one writeMultipleRegisters —
  //    this is what makes the DO pwm triple "computed together" without either side knowing it's PWM;
  //  - a mismatched mode write (schema.tag's value naming a variant this feature's options exclude for
  //    this channel) throws RejectedPayload (05a §6.4) before any write reaches the wire.
}
```

A worked trace against §3's `DO` feature, `onSet({ mode: 'pwm', value: { duty: 4000 } })`: `decodeValue`/`encodeValue` walk `DOValue`'s `union` arm, resolve `variant: pwm` to `code: 1`, write register 2 (`mode`) then register 30+`channelIndex` (`pwm.value`, one register — no batching needed, since `pwm.value` is now a bare `uint16`, not a struct, per §3's split). Against `AO`'s feature from the same board, `onSet({ mode: 'current20', value: 8000 })` on channel 0 (AO1): `decodeValue` finds `opt.channels = [3, 4]`, doesn't include `1` (1-based, matching the YAML), and `encodeValue` throws `RejectedPayload` before either register write.

## 5. Scan cache and block-scan loop

Owned entirely by this file. `driver-kit` does not provide a generic scan/staleness primitive — see the note on `packages/driver-kit/README.md` and 05a §5, both amended alongside this file — so nothing here is layered on a lower-level helper; it's plain scheduling against this package's own `ModbusTransport`.

```ts
// @evok-node/modbus — hw-modbus-kit
interface ScanCache {
  get(addr: ResolvedAddress): number | boolean;      // decodeWord + scale already applied
  lastScanAt(blockId: string): Millis | null;
}

class DefaultScanCache implements ScanCache {
  private blocks = new Map<string, { words: readonly number[] | readonly boolean[]; at: Millis }>();
  constructor(private defBlocks: readonly ResolvedBlock[], private clock: Clock) {}

  updateFromScan(block: ResolvedBlock, raw: readonly number[] | readonly boolean[]) {
    this.blocks.set(block.id, { words: raw, at: this.clock.now() });
  }
  get(addr: ResolvedAddress): number | boolean { /* locate the owning block, decodeWord, applyScale — §4's leaf case */ }
  lastScanAt(blockId: string): Millis | null { return this.blocks.get(blockId)?.at ?? null; }
}

function startScanLoop(tx: ModbusTransport, unitId: number, blocks: readonly ResolvedBlock[], cache: DefaultScanCache, rates: RateTable, scheduler: Scheduler): () => void {
  const stop = blocks.map(b => scheduler.every(rates[b.rate], async () => {
    const raw = b.type === 'coil' ? await tx.readCoils({ unitId, address: b.start, count: b.count })
                                   : await tx.readHoldingRegisters({ unitId, address: b.start, count: b.count });
    if (raw.ok) cache.updateFromScan(b, raw.result);
    // a failed read leaves the prior snapshot in place — staleness surfaces on the next onGet;
    // nothing is ever thrown out of the scheduler itself, matching 03 §7's "never fails silently
    // into a wrong value" extended to a background loop that has no caller to answer directly.
  }));
  return () => stop.forEach(s => s());
}
```

## 6. The escape hatch — `ModbusKindBinder`

```ts
// @evok-node/modbus — hw-modbus-kit
interface ModbusKindBinder<F extends Record<string, EndpointType | OptionalEndpointType> = any> {
  readonly kind: string;                                           // matches ResolvedFeature.kind
  buildDeviceType(feature: ResolvedFeature): DeviceType<F>;
  bind(ctx: WireBindCtx, feature: ResolvedFeature): { [K in keyof F]?: BindHandlers<any, any, any> };
}
```
Registered via `HwModbusKit.registerKind()` (§8), checked before falling back to §4's generic walk. Two reasons to need one: a `method`-shaped endpoint, since a `CALL` isn't a value with an address and there's nothing for a schema-walker to walk; or a hardware quirk too irregular to express as a schema path at all — a register whose meaning depends on a *different* register's own bit, say. None of the built-in Unipi kinds (`DI`/`DO`/`RO`/`LED`/`AI`/`AO`/`WD`/`PWM_OPT`) register one; this section exists for the driver or plugin that adds a `kind` the generic walk genuinely can't cover, per the universality goal this whole file was written to serve — a new `kind` needs no change here or in `hw-definitions`, only its own binder.

## 7. Handshake

```ts
// @evok-node/modbus — hw-modbus-kit
interface HandshakeResult {
  ok: boolean;
  reason?: 'unreachable' | 'timeout' | 'hardware-id-mismatch' | 'census-mismatch' | 'firmware-below-floor';
  detail?: string;
  variant?: string;   // which firmware-variant file was selected (research/13 §2.2) — diagnostic only
}
```
Runs the identity check (research/13 §2.1 — `hardwareId` where known, `census` otherwise) and firmware-variant selection (§2.2) against a live unit, using this same package's `ModbusTransport`. A non-`ok` result is `08`/`09`'s own cue to refuse the unit outright — "refusal to run, not a warning," per research/13 §2.1 — never something this file downgrades to a log line. Always called before `bindDefinition()`, never after: `bindDefinition()` assumes the `ResolvedDefinition` it's given already came from the variant `handshake()` selected, and does not re-check either census or firmware itself.

## 8. The complete interface

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
  registerKind(binder: ModbusKindBinder): void;                                   // built-ins need none; §6
  handshake(def: UnresolvedDefinition): Promise<HandshakeResult>;                  // §7 — always before bindDefinition
  bindDefinition(def: ResolvedDefinition, rates: RateTable): BoundDefinition;      // §4/§5/§6 combined — the one call 08 and 09 share
}

function createHwModbusKit(
  kit: DriverKit,
  tx: ModbusTransport,                       // one per owning driver instance — embedded, 07 §7
  deps: { clock: Clock; log: Logger; scheduler: Scheduler },
): HwModbusKit;
```

## 9. Placement

This file's home is `packages/modbus` — the same package as `ModbusTransport` and `MODBUS_RAW` (07) — not a package of its own. That's a deliberate widening of what was, until this file, a strictly wire-protocol-only boundary: `modbus` now depends on `driver-kit` and `hw-definitions`, where it previously depended on neither, and its own `README.md` is amended accordingly. The split stays visible in the source tree (`packages/modbus/src/hw-modbus-kit/`) even though the DAG can no longer enforce it as a package edge — `packages/modbus`'s own internal organization is what carries the boundary now, not `.dependency-cruiser.cjs`.

`driver-onboard` (08) and `driver-extension` (09) own transport lifecycle (`open`/`close`) and unit/line topology; each calls `handshake()` then `bindDefinition()` once per unit and never touches `driver-kit` or a register address directly. Their own DAG entry shrinks from `['messaging', 'driver-kit', 'modbus', 'hw-definitions']` to `['messaging', 'modbus', 'hw-definitions']` — `hw-definitions` stays a direct dependency for id/config resolution (naming which definition a `unit:` config key points at), even though every actual binding call now goes through `modbus`.

## 10. Testing

Tier 1, against a fixture `ResolvedDefinition` and the simulator (`design/simulator`) — no hardware:

- Schema-walk roundtrip: a struct with a nested struct field, and a union whose active variant is picked from a live `mode` register, both decode and encode correctly; a union facet path that doesn't match the current variant is never fabricated.
- Channel restriction: a mode `onSet` naming a variant excluded by that channel's own `options[].channels` answers `bad-payload` via `RejectedPayload`, never reaches the transport.
- Contiguous-struct batching: a struct value backed by contiguous registers writes as exactly one `writeMultipleRegisters` call, asserted against the fixture transport's own call log — never split into per-field writes.
- `PWM_OPT` binds exactly once regardless of how many `DO` channels the fixture definition declares.
- Handshake refusal: a `census` mismatch, a `hardwareId` mismatch, and a board below every variant's `minFirmware` floor each answer a non-`ok` `HandshakeResult` naming the right `reason`, and `bindDefinition()` is never reached in any of the three.
- Scan staleness: a failed block read leaves the prior snapshot in `ScanCache`; the next `onGet` reports `stale: true` off `lastScanAt`, never throws, never blocks.
- The registry (§6): a fixture `kind` with no registered `ModbusKindBinder` and no manifest-resolvable `DeviceType` fails at `bindDefinition()`, naming the kind; a registered binder for a `method`-shaped fixture kind is used in preference to the generic walk, which never attempts one.

## 11. Open

`driver-kit`'s own surface is still, in its own words, "a guess until a second driver exists." If it later grows a generic scan/staleness primitive once `driver-onewire` or another polling driver needs one too, this file's `ScanCache`/`startScanLoop` should be revisited against it — deferred deliberately now, not decided against permanently.
