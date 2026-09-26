# 10 — 1-Wire driver

## 1. Scope

The 1-Wire bus as a driver like any other. Reached through `owserver` only — the daemon owns the wire protocol and hands back already-decoded, named values; this driver never talks to a DS2482 or a kernel `w1` device directly, and `/sys/bus/w1` is not a supported backend.

The xG18 extension is out of scope entirely. It answers over Modbus RTU like any other extension; that its firmware happens to use 1-Wire internally between itself and its own sensors is the board's own business, invisible on the wire we speak to it. `driver-extension` owns it exactly like any other unit.

**Must not depend on:** any api, `main`, another driver.

Every other driver in this catalogue has a device set that's a fact declared once, at config or at handshake. This one's isn't: 1-Wire sensors arrive and leave the bus at runtime, so the endpoint set is never derived from config. §5 is how that's handled — discovery and adoption, not declaration.

## 2. Configuration

```ts
interface OnewireConfig {
  autogen: boolean;
  transport?: { kind: 'owserver'; host: string; port: number; timeoutMs?: number };
  discovery?: { intervalMs?: number };   // default 60000
  scan?: { intervalMs?: number };        // default 60000; auto-throttled upward — §7
}
```

```yaml
drivers:
  OW1:
    type: onewire
    autogen: true                 # main loads /etc/evok-node/autogen-onewire.yaml — §3

  OW2:
    type: onewire
    autogen: false
    transport: { kind: owserver, host: 127.0.0.1, port: 4304 }
    discovery: { intervalMs: 60000 }
    scan: { intervalMs: 60000 }
```

There is no `devices:` key on this driver, on purpose — see §1.

Rules, checked at config-parse time, same class as 08 §2's:

- **`autogen: true` is exclusive with `transport:`.** The file (§3) supplies it instead.
- **`autogen: false` requires `transport:`.**
- **A second physical adapter needs its own `owserver` process and its own driver instance**, never a second bus named inside one instance. `owserver` already merges every adapter it's given into one flat namespace of ROM addresses, and those addresses are globally unique, so nothing here needs to disambiguate by bus — one instance is one `owserver` connection, full stop.
- **Two `onewire` instances both `autogen: true`** both resolve the same file and the same endpoint. Not caught — the same acknowledged gap 08 §7 already states for two `autogen: true` onboard instances, left as an operational note rather than tooling.

## 3. `autogen-onewire.yaml`

```yaml
# /etc/evok-node/autogen-onewire.yaml — written only by autogen.py, alongside autogen-onboard.yaml
schema: 1
generatedAt: 2026-09-24T10:03:00Z
generatedBy: run.d
fingerprint: "sha256:9c2a..."   # independent of autogen-onboard.yaml's own fingerprint — unrelated facts
transport:
  kind: owserver
  host: 127.0.0.1
  port: 4304
```

Same three callers as 08 §3 (`run.d`, `postinst`, this driver's own `configure()`), same single `autogen.py` (08 §4) — it now writes two files per run instead of one, each fingerprinted separately, because the facts behind them are unrelated: onboard's fingerprint hashes product id and `CARDS`; this one hashes whether `owserver` is installed and whether the controller supports bus power control. One shared fingerprint would go stale for the wrong reason.

Scope stays bus-level only — host, port, power control — never a device list, exactly what classic EVOK's own `OWFS` autogen section ever emitted (research/03 §2). Autogen never described a 1-Wire sensor there either; that isn't something this design drops, it's something classic EVOK never had.

## 4. The chip catalog

A 1-Wire chip definition is the same envelope research/13 §2 already defines for Modbus, with `transport: onewire` and `identifies.familyCode` — the fixed one-byte code every ROM address starts with — in place of `boardCodes`. `features:` is the same flat list a Modbus definition already has: each entry becomes its own independently-addressed device, never a single struct with many fields.

```yaml
# packages/hw-definitions/definitions/onewire/dallas/ds18b20.yaml
schema: 1
id: onewire/dallas/ds18b20
transport: onewire
vendor: dallas
device: ds18b20
name: "Dallas DS18B20 digital thermometer"

identifies:
  familyCode: "28"

features:
  - kind: unipi.temp
    attribute: temperature
```

```yaml
# packages/hw-definitions/definitions/onewire/maxim/ds2438.yaml
schema: 1
id: onewire/maxim/ds2438
transport: onewire
vendor: maxim
device: ds2438
name: "Maxim DS2438 multi-value sensor"

identifies:
  familyCode: "26"

features:
  - kind: unipi.temp
    attribute: temperature
  - kind: unipi.ai
    attribute: VDD
    mode: voltage10
  - kind: unipi.ai
    attribute: VAD
    mode: voltage10
  - kind: unipi.ai
    attribute: vis
    mode: voltage10
  - kind: unipi.humidity
    attribute: HIH4000/humidity
    disabled: true
  - kind: unipi.humidity
    attribute: HIH5030/humidity
    disabled: true
  - kind: unipi.humidity
    attribute: HTM1735/humidity
    disabled: true
  - kind: unipi.humidity
    attribute: DATANAB/humidity
    disabled: true
  - kind: unipi.humidity
    attribute: humidity
    disabled: true
```

`kind` names an existing, generic `DeviceType` — `unipi.temp`, `unipi.humidity`, `unipi.ai` (07a §10) — resolved through the same deviceKind manifest every other driver uses (02 §4, 05a §3.5). Reusing them is deliberate: a 1-Wire temperature reading is not a different *kind* of thing from an IAQ temperature reading, only a different way of reaching one. `unipi.ai` is chosen over `unipi.ao` for voltage because `VDD`/`VAD`/`vis` are read-only measurements; `unipi.ao` is a writable channel, and its already-declared `voltage10` variant fits DS2438's range with no schema change.

`attribute` names exactly the property `owserver` exposes for that ROM id — `temperature`, `VDD`, `HIH4000/humidity`. It is not an address in the Modbus sense: `owserver` has already done whatever scratchpad or paged-memory read the chip's own protocol requires and handed back a decoded value under that name before this driver ever sees it. There is nothing more raw available without bypassing `owserver` entirely, which this driver does not do (§1).

**`disabled: true`** flips a feature's default off. Everything else defaults on. This exists because some `owserver` properties are synthetic and depend on wiring the chip's own family code can't tell us about — DS2438 is a generic ADC; which humidity sensor (if any) is wired to it is not a fact `familyCode 26` carries. Shipping all five humidity variants disabled-by-default, rather than guessing one, lets a specific adopted device (§5) turn on the one that's actually real for it.

**Directory and packaging**, mirroring 01-Package.md §3.1 exactly, transport segment swapped:

```
packages/hw-definitions/definitions/onewire/dallas/ds18b20.yaml     # this repo, build time
/etc/evok-node/hw_definitions/onewire/dallas/ds18b20.yaml           # deployed, Debian conffile
/etc/evok-node/hw_definitions/custom/onewire/acme/...               # operator's own, never touched by us
```

Same `evok-node-data` package, same install path, same `custom/` escape hatch — nothing new.

**The familyCode index is this driver's own responsibility, not a new `hw-definitions` capability.** Every other resolution path in this catalogue is a point lookup: config names an exact id, one file loads. `driver-onewire` has no id to look up — only a family code read off a live ROM address — so at `configure()` it walks its own `onewire/` catalog root and builds a `familyCode → definition` index in memory. `hw-definitions` keeps doing per-file parse and validation exactly as it does for Modbus; it never gains a "resolve by field" API of its own.

## 5. Discovery and adoption

Three actions, all `method`-shaped (`effect: 'mutates'` for the first and third):

| Method | Effect | Does |
|---|---|---|
| `discover` | mutates | Scans the bus now (also runs on `discovery.intervalMs`, default 60 s). Refreshes the live candidate list: ROM id, resolved family/kind if a definition matches, adopted-or-not. |
| `store` | mutates | `{ romId, label?, endpoints? }` — adopts or updates a device. Binds one device per feature the current `endpoints` config leaves enabled; persists the record to `driver-kv-store`'s namespace for this instance (05a §3.6, 06). |
| `remove` | mutates | `{ romId }` — unbinds every tail bound for it and deletes its KV record. The only way a device leaves for good. |

Nothing is bound, and nothing is addressable, until `store` is called. `discover` only ever reports — it never binds anything itself. This is deliberate: `label` and per-endpoint `enabled`/`scanFactor` have nowhere to live before a device has actually been looked at, so adoption is the one moment that config is set, not a side effect of a chip merely being present on the bus.

The KV record `store` writes, one per adopted ROM id:

```ts
interface AdoptedOnewireDevice {
  label?: string;
  endpoints?: Record<string /* attribute */, { enabled?: boolean; scanFactor?: number }>;
}
```

An attribute absent from `endpoints` takes its feature's own default — enabled unless the definition says `disabled: true` (§4), `scanFactor: 1`. `store` on an already-adopted `romId` merges into the existing record and re-binds accordingly — an endpoint newly disabled is unbound, one newly enabled is bound, `label` alone can be changed without touching `endpoints` at all.

A `romId` discovered whose family code matches no catalog entry appears in the candidate list as unresolved — visible, but not `store`-able until a definition exists for it (the `custom/` root, §4, is exactly how a third-party chip gets one).

## 6. Binding

Per adopted device, per enabled feature: resolve `feature.kind` through the deviceKind manifest (02 §4, 05a §3.5) to a real `DeviceType`, then `bindDevice()` it under a tail derived from the ROM id and the feature's own `attribute` — `2895DCD509000035.VDD` alongside `2895DCD509000035.VAD`, `.vis`, and so on; a chip with one feature binds a bare `2895DCD509000035`. `unbindDevice()` on `remove` tears all of a device's tails down together.

Because `owserver` already decoded the value, there is no per-chip driver code and no register-block walk to write, the way 07a §6 needs for Modbus. One generic handler covers every feature of every chip: `onGet` is `ctx.tx.readAttribute(romId, feature.attribute)`, full stop. An escape hatch mirroring 07a §7's `ModbusKindBinder` stays reserved for a chip that genuinely needs more than "read one named attribute" — neither shipped chip family does, since `owserver` already does the hard part for both.

## 7. Scan loop and caching

`scheduleRepeating` (04 §5.2), `overrunPolicy: 'skip'` — a stale reading next cycle is harmless, which is exactly the case that policy is for. Default interval 60 s, from `scan.intervalMs`.

**Auto-throttle.** The configured interval is a floor, not a guarantee: if the number of currently enabled endpoints across every adopted device would not fit inside it, the effective interval is lengthened to whatever it actually takes. This is logged once — a rate-limited warning naming the requested and effective interval, not one line per cycle — because a silently-slower scan than what an operator configured is exactly the kind of thing research/04's "name the failing dependency" lesson already asks for. No shared rate-limiter exists yet in 04 for this; the cooldown is this driver's own small piece of bookkeeping, not a reused mechanism.

**`scanFactor`** (§5) divides the cycle per endpoint, the same idea as a Modbus block's `frequency` divisor (research/03 §2): `scanFactor: 10` means that endpoint is actually read on every tenth tick, not every one — a way to deprioritize a rarely-changing or low-value reading without a second timer.

**The cache is the only thing a `GET` ever reads.** The scan loop is the only writer. Every reading carries `readAt`/`stale` the same way 07a's scan cache already produces them; an event fires only when a value actually changes, never on a tick that reread the same number. This is the direct fix for the #101/#30 bug class: one adopted device going quiet updates only its own cache entries to `stale` and eventually `unreachable` — it never blocks, slows, or freezes anything else's read.

## 8. Failure modes

**`owserver` unreachable**, at `configure()` or discovered later: the driver reports `degraded`, with a one-line diagnostic naming the endpoint it couldn't reach — never a startup crash, and never a silent retry with nothing surfaced. Discovery and the scan loop both keep retrying in the background.

**An adopted device that stops answering** stays bound. Every one of its enabled endpoints answers `unreachable`/`stale` (03 §7) — the same vocabulary every other driver already uses for "the wire didn't answer" — and it is re-probed on the normal schedule. Nothing about a quiet bus ever unbinds a device; only `remove` does that (§5). This is what makes "exposed by default" and "what a disappeared sensor reads as" — both open in the original memo — into ordinary, already-existing behavior rather than something bespoke.

## 9. Packaging

Covered by 01-Package.md §3.1: same `evok-node-data` package, same `evok-node`/`evok-node-data` split, same `run.d`/`postinst` mechanics as 08 §9 already narrates for onboard. Nothing about 1-Wire changes the packaging story — only the catalog subtree and the second `autogen-*.yaml` file are new (§3, §4).

## 10. Testing

Tier 1 (`design/basics/03-Testing.md`), against a fixture/simulated `owserver` — no hardware:

- Config parse: `autogen: true` with `transport:` present is rejected; `autogen: false` missing `transport:` is rejected.
- Catalog index: a fixture `onewire/` root with two definitions builds a correct `familyCode → id` index at `configure()`; a `familyCode` claimed by two definitions is a load-time error.
- Discovery: `discover()` against a fixture bus reports a known-family ROM id with its resolved kind and an unresolved one as unresolved; a ROM id already adopted is reported as such, not as new.
- Adoption: `store` binds exactly the features left enabled by its `endpoints` (defaults from `disabled`, §4, when omitted); a later `store` on the same `romId` merges rather than replaces; `remove` unbinds every tail and deletes the KV record — a subsequent `discover` reports it as unadopted again, not as gone.
- Reachability, never fatal: a fixture ROM id whose simulated `owserver` read fails answers `unreachable` on every enabled endpoint, stays listed, and recovers without a restart once the fixture read succeeds again — the #101 case, asserted with at least two adopted devices so the failing one is shown not to affect the other.
- Scan throttling: enough fixture-adopted endpoints to exceed the configured interval triggers the effective-interval warning exactly once per change of value, never once per tick.
- `scanFactor`: an endpoint with `scanFactor: 10` is read on the tenth tick and not before.
- One full round trip: `store` a fixture DS18B20-shaped ROM id → scan loop populates its cache → `GET` answers with `readAt`/`stale` → `remove` → the tail answers `unknown-address`.
