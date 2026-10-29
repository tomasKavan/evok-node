# 12g — MIM-B19N driver

## 1. Scope

Package: `packages/driver-mimb19n` (`@evok-node/driver-mimb19n`). Config `type: mimb19n`. Kinds `mimb19n.*`.

Runs the Samsung MIM-B19N modules of one flat — one per FJM outdoor unit — and their indoor units (research/18). Its endpoints are raw driver-kit devices (05a), shown and controlled in the Inspector UI (16). The Home UI sees an indoor unit through `RoomAirConditioner` (12c-10); the templates are in the `@evok-node/driver-mimb19n/home` subpath (§6).

```
RS-485 (basement PLC) ── Raw Relay Driver (07 §6, type modbus-kit)   owns the line, 9600 8E1
                             │ modbus-remote (07 §4.1)
flat PLC              driver-mimb19n                                  MIMs → mimb19n.module, .outdoor, .indoorUnit
                             │ role `unit`
                      room-ac-from-mimb19n (12c-10 §3.2)  →  home.RoomAirConditioner
```

- The driver embeds the Modbus engine (07 §7): one `ModbusTransport`, its typed methods. It never binds `MODBUS_RAW`; nothing above it sees a register address.
- The register layer is the `mim-b19n` library, one client per MIM (§9).
- Every flat's instance reaches the same line through the relay and polls only its own MIMs. The line's arbitration is the Raw Relay Driver's (07 §2); the gap a MIM needs is this driver's (§4).

**Not for:**

- Room control. 12c-10's room controller decides; this driver does what it is told.
- AI modes, SmartThings, Samsung's own central controllers, a direct NASA bus (research/18 §1, §4.4).
- Discovering indoor units. They are configured (§2), as 09's units are.

**Must not depend on:** any api, `main`, another driver. The home templates import `driver-home`'s types (12a §3); the driver itself never does.

## 2. Configuration

```ts
interface IndoorUnitConfig {
  readonly iu: number;                     // 0–47: the indoor unit's address (research/18 §1.1)
  readonly model: string;                  // a key of the model table, below
}

interface MimB19nConfig {
  readonly transport: ModbusTransportConfig;   // 07 §4 — modbus-remote in this house
  readonly gapMs?: number;                     // after every response of one MIM; default 50, min 10 (§4)
  readonly statusMs?: number;                  // indoor unit block; default 10 000
  readonly extrasMs?: number;                  // extra registers; default 30 000
  readonly outdoorMs?: number;                 // module and outdoor registers; default 30 000
  readonly nasaWrites?: boolean;               // default false (§5.2)
  readonly modules: readonly {
    readonly unit: number;                     // the MIM's slave address, 1–247
    readonly indoorUnits: readonly IndoorUnitConfig[];
  }[];
}
```

```yaml
drivers:
  ac:
    type: mimb19n
    transport: { kind: modbus-remote, url: wss://basement-plc/api, driverId: rs485-ac }
    modules:
      - unit: 3
        indoorUnits:
          - { iu: 0, model: AR70F09C1AWNEU }
          - { iu: 1, model: AR70F07C1AWNEU }
          - { iu: 2, model: AR70F18C1AWNEU }
      - unit: 4
        indoorUnits:
          - { iu: 0, model: AR70F09C1AWNEU }
```

Fatal at `configure()`: a `unit` twice; an `iu` twice in one module; an `iu` outside 0–47; a `model` not in the table; `gapMs` below 10.

**Model table.** What a unit supports is not readable — B+1 reports a wall unit as "IU" (research/18 §5) — so it is shipped, per model:

```ts
interface IndoorModel {
  readonly modes: readonly ('auto' | 'cool' | 'dry' | 'fan' | 'heat')[];
  readonly fan: readonly ('auto' | 'low' | 'medium' | 'high')[];
  readonly swingLeftRight: boolean;                           // up/down always
  readonly windFree: boolean;                                 // in cool, dry and fan only
  readonly altModes: readonly ('sleep' | 'quiet' | 'fast')[];  // through 0x4060 (§5.2)
  readonly setpoint: { readonly heat: [number, number]; readonly cool: [number, number]; readonly stepC: number };
}
```

| Model | Modes | Fan | Left/right | WindFree | Alt modes | Setpoint |
|---|---|---|---|---|---|---|
| `AR70F07C1AWNEU`, `AR70F09C1AWNEU`, `AR70F18C1AWNEU` | all five | auto–high | yes | yes | `fast` | heat 16–30, cool 18–30, step 1 °C |

From research/18 §4.3: Eco is not offered on multi systems, so it is never an alt mode; `sleep` and `quiet` are Open (§10). A new model is a row here.

Nothing is kept in KV. After a restart the room device restores and writes its own state (12c-10 §1.1).

## 3. Endpoints

Bound at `attach()` (05a §3.8), one set per configured MIM and indoor unit; the table never changes. Tails start with the MIM's unit, as 09 §3a's do.

| Tail | Kind | What |
|---|---|---|
| `<unit>.module` | `mimb19n.module` | the MIM: error bits, tracking, extras |
| `<unit>.outdoor` | `mimb19n.outdoor` | the outdoor unit: error, defrost, heat/cool, state, temperature |
| `<unit>.iu.<iu>` | `mimb19n.indoorUnit` | one indoor unit |

```ts
// @evok-node/driver-mimb19n
const Celsius = Codecs.float32({ unit: '°C' });
const Mode    = Codecs.string({ enumValues: ['auto', 'cool', 'dry', 'fan', 'heat'] });
const Fan     = Codecs.string({ enumValues: ['auto', 'low', 'medium', 'high'] });
const HeatCool = Codecs.string({ enumValues: ['cool', 'heat', 'coolMain', 'heatMain'] });
const Error   = Codecs.optional(Codecs.uint16({ min: 100, max: 999 }));   // absent ⇒ no error

const OutdoorState = Codecs.struct({
  defrost:  Codecs.bool(),
  heatCool: Codecs.optional(HeatCool),
  error:    Error,
});

export const Module = device('mimb19n.module', {
  error:      reading(Codecs.struct({ address: Codecs.bool(), r1r2: Codecs.bool(), tracking: Codecs.bool() }), { subscribe: true }),   // PDU 0
  extras:     reading(Codecs.string({ enumValues: ['pending', 'registered', 'failed'] }), { subscribe: true }),                         // §5.1
  reregister: method('mutates', Codecs.void),
});

export const Outdoor = device('mimb19n.outdoor', {
  error:        reading(Error, { subscribe: true }),                                                        // PDU 1
  defrost:      reading(Codecs.bool(), { subscribe: true }),                                                // PDU 2
  heatCool:     optional(reading(Codecs.optional(HeatCool), { subscribe: true })),                          // 0x8003
  state:        optional(reading(Codecs.optional(Codecs.string({
                  enumValues: ['stop', 'safety', 'normal', 'deice', 'prohibit', 'other'] })), { subscribe: true })),   // 0x8001
  temperature:  optional(reading(Codecs.optional(Celsius), { subscribe: true })),                           // 0x8204
  compressorHz: optional(reading(Codecs.optional(Codecs.uint16({ unit: 'Hz' })), { subscribe: true })),     // 0x8238
});

export const IndoorUnit = device('mimb19n.indoorUnit', {
  comm:           reading(Codecs.struct({ exist: Codecs.bool(), typeOk: Codecs.bool(), ready: Codecs.bool(),
                                          commError: Codecs.bool() }), { subscribe: true }),        // B+0
  power:          channel(Codecs.bool(), { subscribe: true }),                                      // B+2
  mode:           channel(Mode, { subscribe: true }),                                               // B+3
  fan:            channel(Fan, { subscribe: true }),                                                // B+4
  swingUpDown:    channel(Codecs.bool(), { subscribe: true }),                                      // B+5
  swingLeftRight: optional(channel(Codecs.bool(), { subscribe: true })),                            // 0x407E
  setpoint:       channel(Celsius, { subscribe: true }),                                            // B+8
  temperature:    reading(Celsius, { subscribe: true }),                                            // B+9 — the unit's own sensor
  discharge:      reading(Celsius, { subscribe: true }),                                            // B+10
  windFree:       channel(Codecs.bool(), { subscribe: true }),                                      // B+30: 9 / 0
  altMode:        optional(channel(Codecs.string({ enumValues: ['none', 'sleep', 'quiet', 'fast'] }), { subscribe: true })),   // 0x4060
  realMode:       optional(reading(Codecs.optional(Codecs.string({
                    enumValues: ['auto', 'cool', 'dry', 'fan', 'heat', 'autoCool', 'autoDry', 'autoFan', 'autoHeat'] })), { subscribe: true })),   // 0x4002
  thermoOn:       optional(reading(Codecs.bool(), { subscribe: true })),                            // 0x4028
  defrost:        optional(reading(Codecs.bool(), { subscribe: true })),                            // 0x402E
  outdoor:        reading(OutdoorState, { subscribe: true }),                                       // its MIM's outdoor unit, copied
  filterAlarm:    reading(Codecs.bool(), { subscribe: true }),                                      // B+6
  clearFilter:    method('mutates', Codecs.void),                                                   // B+7 = 1
  error:          reading(Error, { subscribe: true }),                                              // B+13
  remoteLock:     channel(Codecs.bool(), { subscribe: true }),                                      // B+14: 0x6363 / 0x0000
  localChange:    reading(Codecs.optional(Codecs.struct({ at: Codecs.timestamp(), fields: Codecs.array(Codecs.string()) })), { subscribe: true }),
  features:       reading(Features),                                                                // the model's row (§2), as data
});
```

- Register meanings are research/18 §2 and §3's. Values outside an enum — a mode the MIM reports that isn't listed — log a warning and keep the last value.
- The `optional` fields come from extra registers (§5.1). They are bound while `extras` is `registered`; `swingLeftRight` and `altMode` only when the model has them.
- `outdoor` is on every indoor unit so the template needs no second role (§6).

### 3.1. A `SET`

| `SET` | Answer |
|---|---|
| a value the model doesn't support (mode, fan step, setpoint range), or `windFree: true` while the unit heats | `bad-payload` (`RejectedPayload`, 05a §3.5) |
| `altMode` or `swingLeftRight` without `nasaWrites` | `bad-payload` |
| the value last read | `ok`, nothing sent — the MIM sends every write on, repeats too (research/18 §2) |
| the unit not ready (`comm` bits 0–2 ≠ 7), or the MIM not answering | `unreachable` |
| otherwise | FC6 (an extra: FC6 on its custom register); answered with the echoed value. The unit is read again 1 s later |

- `setpoint` is rounded to the model's step before it is compared or sent.
- A channel's value is always the last one read, never the one written: the MIM updates a register only when the unit reports it (research/18 §2). Right after a `SET`, the channel may still show the old value until the read 1 s later.

### 3.2. Local change

The driver keeps, per field, the last value it wrote and when. A read value that differs from it — not within 10 s of that write — is a change made elsewhere: the IR remote, the SmartThings app. `localChange` gets `{ at, fields }`. 12c-10 decides what follows (`onLocalChange`, 12c-10 §1.2). With nothing written yet, the first read is never a local change.

## 4. Polling

- **One request in flight per MIM**, and `gapMs` after each of its responses. 07's t3.5 pacing is ≈ 4 ms at 9600 baud, below the manual's 10 ms; 50 ms was stable in practice (research/18 §6). Requests to different MIMs may interleave on the line.
- **Per MIM, in turn:**

  | What | Request | Every |
  |---|---|---|
  | each indoor unit's block | FC3 B+0 … B+31 | `statusMs` |
  | each indoor unit's extras | FC3 B+32 … B+36 | `extrasMs` |
  | module and outdoor | FC3 PDU 0 … 2; FC3 PDU 4 … 8 | `outdoorMs` |

- **Writes first.** A write waits only for the request in flight; the read after a write goes next.
- **Stale.** A field not refreshed within three of its periods marks its device stale (05a §4b), which folds into the home device's `reachable` (12a §4.2).
- **Budget.** One indoor unit ≈ 0.09 s for its block and 0.03 s for its extras, plus gaps (research/18 §6). This flat's six units take ≈ 1 s of line time per 10 s; the house's ~18 units, all flats together, ≈ 3–4 s per round.

## 5. Start and extras

### 5.1. Sequence

1. Open the transport. Per MIM, read PDU 0. While `tracking` is set — up to 10 min after the MIM powers on (research/18 §1.1) — try again every 10 s; its devices are not reachable.
2. Read each configured indoor unit's B+0. Ready only with bits 0–2 = 7. A unit not ready is not reachable; after 10 min a warning names the likely causes: SEG5 not set, a wrong `iu`.
3. **Register the extras** — one FC16 per list, all IDs at once (research/18 §3):

   ```
   PDU 7000: 0x4060 0x407E 0x4002 0x4028 0x402E    → B+32 … B+36 of every indoor unit
   PDU 6000: 0x8003 0x8001 0x8204 0x8235 0x8238    → PDU 4 … 8
   ```

   Then `extras` is `registered` and the extra fields bind. A failed FC16 ⇒ `failed`, the extra fields stay unbound, the rest works; it is tried again on the next of the events below.
4. Start polling (§4).

The lists are registered again whenever the MIM may have lost them — whether they survive a power cycle is not known (research/18 §3): on daemon start, when a MIM answers again after not answering, when `tracking` clears, and on `reregister`. Registering again is harmless. Extra values that all read 0 at once after a while are taken as a lost list: registered again, and a warning logged.

### 5.2. `nasaWrites`

Extras are always read. Writing them — `altMode`, `swingLeftRight` — is not verified on an FJM wall unit through the MIM (research/18 §3), so it is off by default; with it off, both channels answer `bad-payload` to a `SET`. Commissioning switches it on after the test in §8.

## 6. Home templates

In `@evok-node/driver-mimb19n/home`, manifest-loaded (12a §3).

### 6.1. `room-ac-from-mimb19n`

The 12c-10 §3.2 template; its `unit` role is `mimb19n.indoorUnit`, 1.

| `RoomAirConditioner` | ← `mimb19n.indoorUnit` |
|---|---|
| `onOff`, `mode` | `power`, `mode` |
| `fanMode` | `fan` |
| `swing.upDown`, `swing.leftRight` | `swingUpDown`, `swingLeftRight` |
| `special` | `windFree` → `windFree`; `altMode` `sleep`, `quiet` → the same |
| `boost` | `altMode: 'fast'` with `nasaWrites`; otherwise fan `high` and the setpoint at its limit (12c-10 §1.2) |
| the AC setpoint | `setpoint`, written as the compensated value (12c-10 §1.3) |
| the unit's temperature | `temperature` |
| `keypadLockout` | `remoteLock` |
| `filter.alarm`, `clearFilter` | `filterAlarm`, `clearFilter` |
| `fault.code` | `error`, as a string; `outdoor.error` when only that is set |
| `localChange` | `localChange.at` |
| `behavior.supportedModes`, `special` values, limits, step | `features` |
| `available.ac` | not ok while `outdoor.defrost` or `defrost` (`defrost`), or while `outdoor.heatCool` is the opposite of what the room asks (`modeConflict`) |

A mode conflict: one outdoor unit can't heat and cool at once (research/18 §4.1). The room that loses sees `modeConflict` and goes on with its hydronic source, if it has one.

### 6.2. `temperature-from-mimb19n-outdoor`

A `TemperatureSensor` (12c-04) from `mimb19n.outdoor.temperature`; role `outdoor`: `mimb19n.outdoor`, 1. Not reachable while the value is absent. It can feed 12c-10's `outdoor` role. The sensor is at the outdoor unit, which may sit in the sun.

## 7. Failure modes

| Failure | Result |
|---|---|
| link to the basement PLC down | every device not reachable; the room device runs on hydronic only (12c-10 §1.2) |
| a MIM not answering | its devices not reachable; extras registered again when it answers |
| `tracking` set | its indoor units not reachable until it clears |
| an indoor unit not ready | that unit not reachable; the others work |
| extras FC16 failed | extra fields unbound, `extras: 'failed'`; the base registers work |
| a `SET` not seen in the read after it | warning logged; the channel keeps what the unit reports |
| a mode conflict (E161 when reported) | `error` 161; `outdoor.heatCool` tells the template (§6.1) |
| defrost | `outdoor.defrost` / `defrost` true for 5–12 min; heating paused on every indoor unit of that outdoor unit (research/18 §4.2) |

## 8. Commissioning

1. **SEG5 = 1** on every indoor unit, set with the wireless remote; then power-cycle the unit (research/18 §1.1).
2. **Addresses.** Each indoor unit's MAIN address (FJM auto-addressing: E199, K1) is its `iu`. Each MIM's DIP and rotary switches give its `unit`; power-cycle it after a change.
3. **The line.** A Raw Relay Driver on the basement PLC — `type: modbus-kit`, `modbus-rtu`, 9600 baud, even parity — listed in that PLC's `apis.nextgen.drivers` (07 §4.1).
4. **Extras test**, on one MIM, through the Raw Relay Driver:

   ```
   CALL rs485-ac:raw.writeMultipleRegisters { "unit": 3, "address": 7000, "values": [16480, 16510] }   # 0x4060, 0x407E
   CALL rs485-ac:raw.readHoldingRegisters  { "unit": 3, "address": 82, "count": 2 }                   # IU 0: B+32, B+33
   CALL rs485-ac:raw.writeSingleRegister   { "unit": 3, "address": 82, "value": 3 }                    # fast — seen on the unit?
   ```

   Then power-cycle the MIM and read B+32 again. If the write works, set `nasaWrites: true`; the result goes to research/18 §3.

## 9. The `mim-b19n` library

One `MimClient` per MIM, over an adapter from 07's `ModbusTransport`:

```ts
// @evok-node/driver-mimb19n — internal
function mimTransport(t: ModbusTransport, unitId: number, deadline: () => Deadline): IModbusTransport {
  const call = async <T>(o: Promise<CallOutcome<T, ModbusExceptionKind>>): Promise<T> => {
    const r = await o;
    if (r.ok) return r.result;
    throw new MimCallError(r);                    // the driver maps it back to a CallOutcome
  };
  return {
    isConnected: true,
    connect: async () => {}, disconnect: async () => {},   // the line is 07's
    readHoldingRegisters:   (address, count)  => call(t.readHoldingRegisters({ unitId, address, count, deadline: deadline() })),
    readInputRegisters:     (address, count)  => call(t.readInputRegisters({ unitId, address, count, deadline: deadline() })),
    writeSingleRegister:    (address, value)  => call(t.writeSingleRegister({ unitId, address, value, deadline: deadline() })).then(() => {}),
    writeMultipleRegisters: (address, values) => call(t.writeMultipleRegisters({ unitId, address, values, deadline: deadline() })),
  };
}
```

- Pacing, priority and the one-in-flight rule are the driver's (§4), not the library's.
- The library is used for register addresses, decoding and writes; this driver doesn't repeat its register table.
- **Library changes, by pull request** (research/18 §8.2): the communication status bits (b0 Exist … b3 error) and a ready check of bits 0–2 = 7; the remote lock `0x6363`; WindFree `9`; 360 Spot `106`; one indoor extras list for every unit instead of one per unit; writing an extra register.
- How the library reaches the workspace (npm or a vendored package): §10.

## 10. Open

- **Extras on the hardware** — whether the list survives a MIM power cycle; whether `0x4060` and `0x407E` writes work on an FJM wall unit. Test in §8; until then `nasaWrites` is off.
- **`sleep` and `quiet` on the AR70F** — not in its manual (research/18 §4.3). Not in the model table until seen.
- **The mode conflict on AJ…TXJ** — E161 and what the losing unit does (research/18 §4.1). §6.1 relies on `outdoor.heatCool`.
- **A 0.5 °C setpoint** through B+8 — the table uses 1 °C steps.
- **One FC3 across unit blocks** — would cut requests (§4); not known whether the MIM allows it.
- **The library in the workspace** — published to npm or vendored as a package. → M3.15.

## 11. Testing

Tier 1 (basics/03), fake `Clock`, fake `ModbusTransport` with a simulated MIM:

- Polling: order and periods, one request in flight per MIM, `gapMs` after each response, writes first, the read 1 s after a write; stale after three periods.
- Start: tracking, then ready only at bits 0–2 = 7; a unit not ready not reachable.
- Extras: registered at start, after the MIM comes back, after tracking clears, on `reregister`; all zeros ⇒ registered again; FC16 failing ⇒ fields unbound, `failed`.
- `SET`: model checks and `bad-payload`; WindFree while heating refused; equal value not sent; setpoint rounded; `nasaWrites` gating; `unreachable`.
- Local change: a read change not written here sets `localChange`; one right after a write doesn't.
- Config: every fatal case of §2.
- `room-ac-from-mimb19n`: every row of §6.1, boost with and without `nasaWrites`, `modeConflict` and `defrost`.
