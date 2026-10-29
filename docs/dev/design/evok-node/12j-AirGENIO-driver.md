# 12j — AirGENIO driver

## 1. Scope

Package: `packages/driver-airgenio` (`@evok-node/driver-airgenio`). Config `type: airgenio`. Kinds `airgenio.*`.

One instance runs one 2VV heat recovery unit with AirGENIO COMFORT control (Venus, research/16) over Modbus RTU. Its endpoints are raw driver-kit devices (05a), shown and controlled in the Inspector UI (16). The Home UI sees the unit through `VentilationUnit` (12c-12); the template `ventilation-from-airgenio` is in the `@evok-node/driver-airgenio/home` subpath.

```
RS-485 ── Raw Relay Driver (07 §6, type modbus-kit)      owns the line, MODBUS_RAW
              │ modbus-relay (same PLC) · modbus-remote (07 §4.1, another PLC)
          driver-airgenio                                 registers → airgenio.unit, .service, .info
              │ role `unit`
          ventilation-from-airgenio (12c-12 §3.4)  →  home.VentilationUnit
```

The driver embeds the Modbus engine (07 §7): it holds one `ModbusTransport` and calls its typed methods. It never binds `MODBUS_RAW`, and nothing above it sees a register address.

**Not for:**

- Schedules: rules (12b). The unit's own week and year timer is kept off (§5.4).
- The unit's demand control (DCV): it needs a sensor wired to the unit. Demand control runs in the home template on the rooms' CO₂ (12c-12 §1.3); the unit stays in manual mode.
- SUPERIOR control (CAV, VAV, airflow in m³/h) and air curtains — other register sets in the same spreadsheet.
- Direct control, calibration, factory and firmware registers.

**Must not depend on:** any api, `main`, another driver. The home template imports `driver-home`'s types (12a §3); the driver itself never does.

## 2. Configuration

```ts
interface AirgenioConfig {
  readonly transport: ModbusTransportConfig;   // 07 §4 — normally modbus-relay
  readonly unitId: number;                     // 1–247; the unit ships with 1
  readonly addressBase?: 0 | 1;                // default 1: PDU address = listed register − 1 (research/16 §2), checked at commissioning (§8)
  readonly pollMs?: number;                    // status and control blocks; default 5000
  readonly gapMs?: number;                     // pause between two requests; default 50
  readonly keepUnitTimer?: boolean;            // default false — §5.4
  readonly syncClock?: boolean;                // default true — §5.4
}
```

```yaml
drivers:
  rs485-2:
    type: modbus-kit
    transport: { kind: modbus-rtu, path: /dev/ttyNS1, baudRate: 9600, parity: odd }   # the unit's default 9600 8O1
  hru:
    type: airgenio
    transport: { kind: modbus-relay, driverId: rs485-2 }
    unitId: 1
```

- Fatal at `configure()`: `unitId` outside 1–247; a `modbus-relay` `driverId` that is not a Raw Relay Driver (07 §4).
- The line runs at the unit's settings; its other members must share them. The unit's board terminates the line (research/16 §2).

## 3. Registers and polling

Listed numbers as in research/16 §3; PDU address = listed − `addressBase`.

| Block | FC | Listed | Read | For |
|---|---|---|---|---|
| `status` | 04 | 15000–15049 | every `pollMs` | `unit` readings (§4) |
| `control` | 03 | 21000–21016 | every `pollMs`, and right after a write | `unit` channels, external changes (§5.5) |
| `service` | 03 | 20001–20045, 25000–25031 | every 60 s, and right after a write | `service`; filter hours |
| `hardware` | 03 | 10100–10164 | at start and after the unit comes back | what is fitted (`info`) |
| `info` | 04 | 16000–16049 | at start and after the unit comes back | firmware; energy (with the module) |
| `clock` | 04 | 17000–17006 | every hour | `info.clock` |

- **One request at a time**, `gapMs` between two; the unit's own pacing is not documented (research/16 §2).
- **Writes** are FC 06, one register each; the unit's echo must equal the value sent, else the answer is `domain-error` `notTaken`. The clock is one FC 16 (§5.4).
- **Staleness**: every reading below is built with 07a §4's `polled()`; `stale` is 07a §8's rule — the block's last read failed, or none has succeeded.
- Enum and bit values are this file's tables (§4, §5.3). Where 2VV's documents disagree (research/16 §5), the commissioning check (§8) decides.

## 4. Endpoints

Bound once at `attach()`; the table never changes. What the unit lacks — a sensor, the preheater, the energy module — is an absent struct member, never another table.

| Tail | Kind | What |
|---|---|---|
| `unit` | `airgenio.unit` | control and status — what the home template uses |
| `service` | `airgenio.service` | service settings, for the Inspector |
| `info` | `airgenio.info` | fitted hardware, firmware, the unit's clock |

```ts
// @evok-node/driver-airgenio
const Permille = Codecs.uint16({ min: 0, max: 1000, unit: '‰' });
const Pct      = Codecs.uint8({ min: 0, max: 100, unit: '%' });
const Celsius  = Codecs.float32({ min: -40, max: 100, unit: '°C' });
const opt      = Codecs.optional;

const Fault = Codecs.string({ enumValues: [
  'supplyFan', 'extractFan', 'supplyFilter', 'extractFilter', 'preheater', 'postheater', 'aqsSensor', 'condensate',
  'config', 'sensorOutdoor', 'sensorExt2', 'sensorSupply', 'sensorExtract', 'sensorExhaust', 'sensorRoom', 'global',
] });

export const Unit = device('airgenio.unit', {
  power:       channel(Codecs.bool(), { subscribe: true }),       // 21001 — false = standby
  level:       channel(Permille, { subscribe: true }),            // 21002 — manual mode; §5.2
  boost:       channel(Codecs.bool(), { subscribe: true }),       // 21009
  nobody:      channel(Codecs.bool(), { subscribe: true }),       // 21010 — Inspector only; the home template doesn't use it
  freeCooling: channel(Codecs.bool(), { subscribe: true }),       // 21011 — night ventilation allowed
  setpoint:    channel(Celsius, { subscribe: true }),             // 21003 — range by `service.tempSensor`
  state:  polled({                                                // 15000, 15001
            on: Codecs.bool(), manual: Codecs.bool(), dcv: Codecs.bool(), fire: Codecs.bool(), boost: Codecs.bool(),
            nobody: Codecs.bool(), freeCooling: Codecs.bool(), preFreeCooling: Codecs.bool(), timer: Codecs.bool(),
            calibration: Codecs.bool(), cooldown: Codecs.bool(), directControl: Codecs.bool(), flowReduction: Codecs.bool() },
          { subscribe: true }),
  fans:   polled({ supply: Permille, extract: Permille }, { subscribe: true }),            // 15013, 15014
  temps:  polled({ outdoor: opt(Celsius), ext2: opt(Celsius), supply: opt(Celsius),       // 15017–15019 (EXT1–3)
                   extract: opt(Celsius), exhaust: opt(Celsius), room: opt(Celsius) },    // 15022, 15023 (INT1, INT2), 15026
          { subscribe: true }),
  heaters: polled({ preheater: opt(Pct), postheater: opt(Pct) }, { subscribe: true }),     // 15036, 15038 — when fitted
  filter: polled({ hours: Codecs.uint16(), maxHours: Codecs.uint16(),                     // 25019, 25020
                   due: Codecs.bool(), warning: Codecs.bool(), error: Codecs.bool() },    // 15000 b13 | 15003 b3; 15002 b4–5; b2–3
          { subscribe: true }),
  faults: polled({ active: Codecs.array(Fault) }, { subscribe: true }),                    // §5.3
  energy: polled({ powerW: opt(Codecs.uint16({ unit: 'W' })), totalKwh: opt(Codecs.uint32({ unit: 'kWh' })) },   // 16005; 16006–16007 L/H — with the energy module
          { subscribe: true }),
  limits: reading(Codecs.struct({ min: Permille, max: Permille, step: Permille })),         // 10112, 10111, 10113
  externalChange: reading(opt(Codecs.struct({ at: Codecs.timestamp(), fields: Codecs.array(Codecs.string()) })), { subscribe: true }),   // §5.5
  resetFilter: method('mutates', Codecs.void),                                             // 21016 = 1
});

const When = Codecs.struct({ month: Codecs.uint8({ min: 1, max: 12 }), day: Codecs.uint8({ min: 1, max: 31 }),
                             hour: Codecs.uint8({ max: 23 }), minute: Codecs.uint8({ max: 59 }) });

const Settings = Codecs.struct({
  ventilationMode: Codecs.string({ enumValues: ['manual', 'dcv'], label: 'Ventilation mode' }),         // 25000
  tempSensor:      Codecs.string({ enumValues: ['supply', 'extract', 'room'], label: 'Control sensor' }), // 25009
  boostMin:        Codecs.uint8({ min: 1, max: 60, unit: 'min', label: 'Boost time' }),                 // 20012
  boostFlowPct:    Pct,                                                                                  // 20013
  boostFromOff:    Codecs.bool({ label: 'Boost button from standby' }),                                 // 20011
  di4:             Codecs.string({ enumValues: ['fire', 'nobody'], label: 'Input 15/16' }),              // 25008 *
  nobodyMin:       Codecs.uint8({ min: 1, max: 60, unit: 'min' }),                                       // 20009 *
  nobodyFlowPct:   Codecs.uint8({ min: 20, max: 50, unit: '%' }),                                        // 20010 *
  freeCooling:     Codecs.struct({ enabled: Codecs.bool(),                                               // 20014 *
                     flowPct: Codecs.uint8({ min: 50, max: 100, unit: '%' }),                            // 20015 *
                     extractC: Codecs.uint8({ min: 12, max: 25, unit: '°C' }),                           // 20016 *
                     from: When, to: When }),                                                            // 20017–20024 *
  supplyDuct:      Codecs.struct({ minC: Codecs.uint8({ min: 15, max: 20, unit: '°C' }),                 // 20035
                     maxC: Codecs.uint8({ min: 25, max: 45, unit: '°C' }),                               // 20034
                     reduceFlow: Codecs.bool() }),                                                       // 20045
  filterMaxHours:  Codecs.uint16({ min: 200, max: 3000, unit: 'h' }),                                    // 25020
  fire:            Codecs.struct({ fans: Codecs.string({ enumValues: ['off', 'both', 'supply', 'extract'] }),   // 25030 *
                     flowPct: Pct }),                                                                    // 25031 *
});

export const Service = device('airgenio.service', {
  settings:      channel(Settings, { subscribe: true }),   // a SET writes only the members that differ
  pendingReset:  reading(Codecs.bool(), { subscribe: true }),   // a * register was written; §5.6
  softwareReset: method('mutates', Codecs.void),           // 10003 = 1
});

export const Info = device('airgenio.info', {
  fitted: reading(Codecs.struct({
    exchanger:  Codecs.string({ enumValues: ['none', 'plate', 'rotary', 'enthalpy'] }),          // 10130
    bypass:     Codecs.string({ enumValues: ['none', 'stepless', 'openClose'] }),                // 10129
    preheater:  Codecs.string({ enumValues: ['none', 'electric', 'water'] }),                    // 10119
    postheater: Codecs.string({ enumValues: ['none', 'electric', 'water', 'wco', 'dx'] }),       // 10123
    energyMeter: Codecs.bool(),                                                                   // 10105
    sensors:    Codecs.array(Codecs.string()),                                                    // 10144–10153 flags set: 'ext1', 'int2', 'room', …
  })),
  firmware: reading(Codecs.struct({ unit: Codecs.uint16(), hardware: Codecs.uint16(), panel: Codecs.uint16() })),   // 16029, 16028, 16045
  clock:    polled({ unit: Codecs.timestamp(), driftS: Codecs.int32({ unit: 's' }) }, { subscribe: true }),        // 17000–17006
});
```

- `*` marks a register 2VV lists as needing a software reset after a change (research/16 §2).
- `temps`, `heaters`, `energy`: a member is present only when `info.fitted` has it and the unit reports a value; a sensor fault (§5.3) makes its member absent.
- `level` and `setpoint` keep their last value while `stale`.

## 5. Behaviour

### 5.1. Start

1. `hardware` and `info` are read; then `attach()` (§4). An unread `hardware` block at `attach()` ⇒ `info.fitted` absent until it is read; `temps` members stay absent until then.
2. The unit's timer and clock are set (§5.4).
3. Polling starts (§3). Nothing is written to `power`, `level` or `boost` — the unit keeps its own state across a restart of evok-node.

The unit coming back after it was not answering (power loss, cable) is a start from step 1.

### 5.2. Level

- `level` SET: clamped to `limits.min`–`limits.max` and rounded to `limits.step` (defaults 200, 1000, 100 ‰); the answer is the value written.
- Only in manual mode: while `state.manual` is false, a SET answers `domain-error` `notManual`.
- `fans` is what the unit runs; it differs from `level` during boost, night ventilation, fire, flow reduction and in standby.

Example: `SET level 450` → written 500 (step 100) → answer `500`; a few polls later `fans { supply: 500, extract: 500 }`.

### 5.3. Faults

`faults.active` lists every bit set, by name:

| Register | Bit → name |
|---|---|
| 15002 | 0 `supplyFan`, 1 `extractFan`, 2 `supplyFilter`, 3 `extractFilter`, 6 `preheater`, 7 `postheater`, 10 `aqsSensor`, 15 `condensate` |
| 15003 | 1 `global`, 4 `config` |
| 15004 | 0 `sensorOutdoor`, 1 `sensorExt2`, 2 `sensorSupply`, 5 `sensorExtract`, 6 `sensorExhaust`, 9 `sensorRoom` |

`supplyFan` and `extractFan` stop the unit; the others leave it ventilating (research/16 §4.8). Filter warnings (15002 bit 4–5) are in `filter.warning`, not here.

### 5.4. Timer and clock

- **Timer.** Without `keepUnitTimer`, `TimeSwGlobalEnable` (21004) is written 0 at start and set back whenever a poll finds it 1. Two schedulers fighting over one unit is worse than either.
- **Clock.** With `syncClock`, at start and when `driftS` exceeds 60 s, the PLC's local time is written to 17000–17006 with `SetFlag` (17007) in one FC 16. The unit evaluates the night-ventilation season by its own clock (research/16 §4.5).

### 5.5. External changes

The panel and the 2VV app write the same SHARE registers as this driver (research/16 §3.1). After each `control` read, a value that differs from the last one read is either this driver's own write — a SET in the last two `pollMs` that wrote that value — or an external change. An external change sets `externalChange { at, fields }` (`power`, `level`, `boost`, `nobody`, `freeCooling`, `setpoint`). What to do with it is the home template's (12c-12 §3.4).

### 5.6. Service settings

- `settings` SET writes only the changed members, in the order of §4, each through §3's write rule. One failing write stops the rest and answers its error; the ones already written stay — `settings` then reads what the unit holds.
- A changed `*` register sets `pendingReset`. `softwareReset()` writes 10003; the unit restarts and does not answer for a while — §5.1 on its return. `pendingReset` clears when the unit answers again. The driver never resets the unit on its own: a reset stops ventilation.

## 6. Failure modes

| Failure | Result |
|---|---|
| Unit not answering | every reading `stale`; a SET answers `unreachable`; the home device not `reachable` (12c-12 §3.4) |
| Raw Relay Driver or link down | as not answering; 07 §4, §4.1 |
| Modbus exception | the SET's answer carries it (07 §5) |
| Echo differs | `domain-error` `notTaken`; the next `control` read shows what the unit holds |
| `level` SET outside manual | `domain-error` `notManual` |

## 7. Placement

In-process, as every Modbus driver (07 §8). One instance per unit; several units on one line are several instances on one Raw Relay Driver.

## 8. Commissioning

Once per unit, with the Inspector and the Raw Relay Driver's `MODBUS_RAW` (07 §6). These settle the points 2VV's documents leave open (research/16 §5, §7):

| Check | How | Expect |
|---|---|---|
| Line | the unit's menu 20 (code 1616): address, 9600, odd | answers at `unitId` |
| Address base | `CALL <raw>:raw.readInputRegisters { unitId: 1, address: 15048, count: 1 }` | the setpoint shown on the panel ⇒ `addressBase: 1` |
| `power` | switch the unit on at the panel | `state.on` true, `power` true |
| `level` in ‰ | `SET level 500` | the panel shows 50 % |
| Boost | `SET boost true`, wait `boostMin` | `boost` back to false by itself — else note it in 12c-12 §3.4's boost end |
| Settings | `service.settings`: `ventilationMode` manual, `boostMin` 60 (the home template ends boost itself), `filterMaxHours` | as set |
| Fitted | `info.fitted` | matches the unit's nameplate and options |

## 9. Testing

Tier 1 (basics/03), fake `Clock`, a fake `ModbusTransport`:

- Address base 0 and 1; block reads and `gapMs`; one request at a time.
- `polled` staleness per block; a block failing keeps the last values.
- `level` clamping and rounding; `notManual`; echo mismatch ⇒ `notTaken`.
- Fault bits → names; fitted flags → absent members.
- External change vs own write within two polls.
- Timer kept off; clock written once on drift > 60 s.
- `settings` SET writes changed members only, stops at the first failure, sets `pendingReset`; `softwareReset` and the return through §5.1.
