# 12f — ISM8i driver

## 1. Scope

Package: `packages/driver-ism8i` (`@evok-node/driver-ism8i`). Config `type: ism8i`. Kinds `ism8i.*`.

The Wolf heating system as seen through its ISM8i (research/19): the boiler, the BM-2 system, the direct circuit, mixer circuits and mixer modules 1–3. Its endpoints are raw driver-kit devices (05a), shown and controlled in the Inspector (16) and used by the central heating driver (12h) on the same PLC. The protocol is the `wolf-ism8` library (design/libs 01); this driver adds config, endpoints and evok-node's rules.

```
Wolf eBus ── ISM8i ──TCP client──►  driver-ism8i  (boiler-room PLC)
                                     │ wolf-ism8: Ism8Server, one Ism8Session
                                     ├─ ism8i.link, .system, .boiler, .circuit, .mixerModule
                                     ├─► driver-central-heating (12h)
                                     └─► temperature-from-ism8i-outdoor (§6) → home.TemperatureSensor
```

- The driver owns the TCP server: the port is a resource with one owner (01 §2).
- **Firmware 1.9 or newer** is assumed: its keepalive (DP 767) is the liveness check (§4). Older firmware is out of scope; commissioning checks it (§7).
- The Wolf keeps its own control — heating curve, mixers, pumps, DHW. This driver reads it and writes only per-circuit settings: program, setpoint correction, economy factor, DHW program and setpoint.

**Not for:**

- Mixer circuits 4–5: not reachable through the ISM8i (research/19 §7.1).
- Solar, ventilation, heat pumps, cascades: not installed. The library has them; another kind each when needed.
- Overriding the boiler: output and setpoint demand (198/199) are read-only here.
- A desired state. What a circuit should be set to is 12h's; this driver keeps no targets.

**Must not depend on:** any api, `main`, another driver. The home template imports `driver-home`'s types (12a §3); the driver itself never does.

## 2. Configuration

```ts
interface Ism8iConfig {
  readonly port?: number;                          // 12004 — as set on the ISM's web page
  readonly host?: string;                          // listen address; default all
  readonly allow?: readonly string[];              // the ISM's IP; absent ⇒ any
  readonly ismHost?: string;                       // for the firmware from its web page (§3); optional
  readonly boilers?: 1 | 2 | 3 | 4;                // default 1
  readonly directCircuit?: boolean;                // default false
  readonly mixerCircuits?: readonly (1 | 2 | 3)[]; // default []
  readonly mixerModules?: readonly (1 | 2 | 3)[];  // default: as mixerCircuits
  readonly writeMinIntervalMs?: number;            // per datapoint, to the session; default 60 000
  readonly maxWritesPerDay?: number;               // per datapoint, rolling 24 h; default 48 (§5.2)
}
```

```yaml
drivers:
  wolf:
    type: ism8i
    allow: [192.168.10.40]
    ismHost: 192.168.10.40
    mixerCircuits: [1, 2, 3]
```

- Devices come from config, never from what happens to arrive: a datapoint the ISM never sends raises no error (research/19 §5), so a device bound from config and silent is visible as such.
- Fatal at `configure()`: a number twice in a list; `maxWritesPerDay` below 1; `writeMinIntervalMs` below 1000.
- Write counts (§5.2) are this driver's only state: KV, saved every 10 min and on stop. Nothing else is kept.

## 3. Endpoints

Bound at `attach()` from config; the table never changes.

| Tail | Kind | From (research/19 §5) |
|---|---|---|
| `link` | `ism8i.link` | the session |
| `system` | `ism8i.system` | 53, 54, 194, 251, 355, 356, 372 |
| `boiler.<n>` | `ism8i.boiler` | base 1 / 14 / 27 / 40, 197–208, 364–367 |
| `circuit.direct`, `circuit.<n>` | `ism8i.circuit` | base 54 / 67 / 80 / 93, 368–371 |
| `mixer.<n>` | `ism8i.mixerModule` | base 114 / 121 / 128 |

```ts
// @evok-node/driver-ism8i
const Celsius = Codecs.float32({ unit: '°C' });
const K       = Codecs.float32({ unit: 'K' });
const T       = (c: TypedCodec<any>) => Codecs.optional(c);    // absent ⇒ not reported since start

export const Link = device('ism8i.link', {
  connected: reading(Codecs.bool(), { subscribe: true }),
  peer:      reading(T(Codecs.string()), { subscribe: true }),
  since:     reading(T(Codecs.timestamp()), { subscribe: true }),
  keepalive: reading(Codecs.struct({ seen: Codecs.bool(), at: T(Codecs.timestamp()) }), { subscribe: true }),
  firmware:  reading(T(Codecs.string()), { subscribe: true }),
  writes24h: reading(Codecs.array(Codecs.struct({ key: Codecs.string(), count: Codecs.uint16() })), { subscribe: true }),
  readAll:   method('mutates', Codecs.void, Codecs.void, { errorKinds: ['notConnected'] }),
});

export const System = device('ism8i.system', {
  outdoorTemperature: reading(T(Celsius), { subscribe: true }),                 // 54, the BM-2's sensor
  fault:              reading(T(Codecs.bool()), { subscribe: true }),           // 53
  lastFaultCode:      reading(T(Codecs.uint8()), { subscribe: true }),          // 372
  present:            reading(T(Codecs.struct({                                 // 251, 355, 356
                        directCircuit: Codecs.bool(), mixerCircuits: Codecs.array(Codecs.uint8()),
                        mixerModules: Codecs.array(Codecs.uint8()), boilers: Codecs.array(Codecs.uint8()) })), { subscribe: true }),
  chargeDhw:          method('mutates', Codecs.void, Codecs.void, { errorKinds: ['rateLimited', 'notConnected'] }),   // 194 = 1
});

export const Boiler = device('ism8i.boiler', {
  fault:              reading(T(Codecs.bool()), { subscribe: true }),
  state:              reading(T(Codecs.struct({ code: Codecs.uint8(), label: Codecs.string() })), { subscribe: true }),   // 20.105, labels as FHEM's for CGB-2
  modulation:         reading(T(Codecs.float32({ unit: '%' })), { subscribe: true }),
  boilerTemperature:  reading(T(Celsius), { subscribe: true }),
  headerTemperature:  reading(T(Celsius), { subscribe: true }),
  returnTemperature:  reading(T(Celsius), { subscribe: true }),
  dhwTemperature:     reading(T(Celsius), { subscribe: true }),
  outdoorTemperature: reading(T(Celsius), { subscribe: true }),
  flueGasTemperature: reading(T(Celsius), { subscribe: true }),
  flame:              reading(T(Codecs.bool()), { subscribe: true }),
  circuitPump:        reading(T(Codecs.bool()), { subscribe: true }),
  dhwPump:            reading(T(Codecs.bool()), { subscribe: true }),
  threeWayValve:      reading(T(Codecs.bool()), { subscribe: true }),            // the raw bit (design/libs 01 §3)
  pressure:           reading(T(Codecs.float32({ unit: 'bar' })), { subscribe: true }),   // 9.006 Pa / 100 000
  boilerSetpoint:     reading(T(Celsius), { subscribe: true }),                  // 364–367
  outputDemand:       reading(T(Codecs.float32({ unit: '%' })), { subscribe: true }),    // 198 — read-only here
  setpointDemand:     reading(T(Celsius), { subscribe: true }),                  // 199 — read-only here
});

const Program    = Codecs.string({ enumValues: ['auto', 'heating', 'standby', 'economy'] });   // 20.102: 0, 1, 2, 3
const DhwProgram = Codecs.string({ enumValues: ['auto', 'continuous', 'standby'] });           // 20.103: 0, 2, 4

export const Circuit = device('ism8i.circuit', {
  fault:              optional(reading(T(Codecs.bool()), { subscribe: true })),  // mixer circuits only
  roomTemperature:    reading(T(Celsius), { subscribe: true }),                  // empty without a BM-2 in the room
  flowSetpoint:       reading(T(Celsius), { subscribe: true }),                  // 368–371
  program:            channel(T(Program), { subscribe: true }),
  setpointCorrection: channel(T(Codecs.float32({ min: -4, max: 4, unit: 'K' })), { subscribe: true }),
  economyFactor:      channel(T(Codecs.float32({ min: 0, max: 10, unit: 'K' })), { subscribe: true }),
  timeProgram:        channel(T(Codecs.uint8({ min: 1, max: 3 })), { subscribe: true }),   // +5…+7, one of three
  dhwProgram:         channel(T(DhwProgram), { subscribe: true }),
  dhwSetpoint:        channel(T(Codecs.float32({ min: 25, max: 65, unit: '°C' })), { subscribe: true }),
});

export const MixerModule = device('ism8i.mixerModule', {
  fault:           reading(T(Codecs.bool()), { subscribe: true }),
  flowTemperature: reading(T(Celsius), { subscribe: true }),
  pump:            reading(T(Codecs.bool()), { subscribe: true }),
  outputA1:        reading(T(Codecs.bool()), { subscribe: true }),
  inputE1:         reading(T(Celsius), { subscribe: true }),
  inputE2:         reading(T(Celsius), { subscribe: true }),
  dhwTemperature:  reading(T(Celsius), { subscribe: true }),
});
```

- **A field is absent until the ISM has reported it** since this driver started. Absent never means 0.
- **Field ↔ datapoint** is the library's table (design/libs 01 §4), by key: `mixerCircuit2.setpointCorrection` ↔ `circuit.2.setpointCorrection`. This driver adds no IDs of its own.
- `dhwSetpoint`'s range is the manual's 25–65 °C, not the CSV's 20–80 (research/19 §5.3).
- `timeProgram` reads the one of the three flags that is set; a `SET` writes `1` to that one, as the Home Assistant integration does. Whether the BM-2 clears the others is not known (research/19 §5.3); the reading shows what it does.
- `firmware` is from `fetchInfo` when `ismHost` is set, once per session; a failure is a warning (§7).

## 4. Connection and liveness

| Situation | Result |
|---|---|
| no session | every device but `link` not reachable; values keep their last state |
| a session starts | `link.connected` true; the library sends one read-all if nothing comes within 60 s (design/libs 01 §5.2) |
| keepalive (DP 767) not seen within 5 min of a session | warning `noKeepalive` — firmware below 1.9? (§7); liveness falls back to the library's silence check |
| no keepalive for 120 s | the library closes the session; the ISM connects again |
| `stale` from the library (silence) | every device but `link` stale (05a §4b) ⇒ not reachable for its consumers (12a §4.2) |
| a new connection | replaces the old session (design/libs 01 §6); values stay and are refreshed |

**A value that jumps.** A temperature that moves by more than 20 K from its last value is held back once: it is taken when the next report confirms it, or after 10 min. One warning per hold. This is the "jump to zero" seen in the field (research/19 §4); the filter is the driver's, not the library's (design/libs 01 §1).

## 5. Writing

### 5.1. A `SET`

As every driver (07a §5, 12 §9): a `SET` answers with the value set, once the write frame is sent; the field keeps showing what the ISM reported, until the ISM reports the new value.

| `SET` | Answer |
|---|---|
| outside the datapoint's range, step or values (design/libs 01 §4) | `bad-payload` (`RejectedPayload`) |
| equal to the value last reported | `ok`, nothing sent |
| no session | `unreachable` |
| within `writeMinIntervalMs` of the last write to it, or over `maxWritesPerDay` | `domain-error` `rateLimited`; a warning on the budget |
| otherwise | sent; answers the value |

`chargeDhw` and `readAll` are calls; they follow the same rules (`rateLimited`, `notConnected`).

### 5.2. The write budget

The BM-2 keeps parameters in EEPROM and Wolf states no write limit (research/19 §6). Three layers keep writes rare:

| Layer | Rule |
|---|---|
| `wolf-ism8` | ≥ `writeMinIntervalMs` between writes to one datapoint — against bugs |
| this driver | ≤ `maxWritesPerDay` per datapoint, rolling 24 h — 48 ⇒ 100 000 writes in about 5.7 years at worst; counts in KV, shown in `link.writes24h` |
| 12h | writes only on a change of a whole 0.5 K step, with hysteresis, at most every 30 min per circuit (M3.3e) |

**Persistence of written values** is not this driver's concern: 12h holds the desired state, compares it with what is reported, and writes only on a difference — after a reconnect, a read-all or a change of demand. A BM-2 that came back from a power cut with other values is corrected the same way.

## 6. Home template — `temperature-from-ism8i-outdoor`

In `@evok-node/driver-ism8i/home`. A `TemperatureSensor` (12c-04) from `ism8i.system.outdoorTemperature`; role `system`: `ism8i.system`, 1. Not reachable while the value is absent. It feeds 12c-10's `outdoor` role in rooms with or without an AC; from another PLC it is imported like any home device (12a §4b).

## 7. Commissioning

1. **Firmware.** On the ISM's web page ("Übersicht"): 1.9 or newer. Older ⇒ an update by Wolf service before use (research/19 §3).
2. **Target.** Netzwerk → Kommunikationspartner: the boiler-room PLC's IP and `port`; restart the ISM (button 5–10 s).
3. **BM-2 A26 "Freigabe Smarthome"** on; writes are reported to need it (research/19 §6).
4. **Check.** `link.connected`, then `link.keepalive.seen` within a minute; `system.present` lists the configured circuits and modules.
5. **Read-all.** `CALL wolf:link.readAll` — every configured device fills within about 2 min. This also tests the 12-byte request (design/libs 01 §11).
6. **One write.** `SET wolf:circuit.1.setpointCorrection 0.5`, watch it reported, then back to its value. Note the result in research/19 §6.

## 8. Failure modes

| Failure | Result |
|---|---|
| ISM silent, keepalive gone | session closed after 120 s; devices not reachable until it reconnects |
| ISM pointing elsewhere, or the port taken | no session; `link.connected` false; a `listen` failure is an error at start, retried every 30 s |
| a connection from an IP outside `allow` | refused, warning |
| a datapoint never reported | its field stays absent |
| a write refused by the BM-2 | not visible as such: the reported value doesn't change; 12h sees the difference and tries again within its budget |
| write budget spent | `rateLimited` until the window allows; warning |
| KV not reachable | counts start from 0; warning |

## 9. Open

- **Mixer circuits 4–5.** Asked of Wolf CZ (research/19 §7.1). An answer may add a source here or in 12h.
- **The write rate.** 48 a day is a guess; raised if Wolf says the BM-2 keeps these values in RAM.

## 10. Testing

Tier 1 (basics/03), fake `Clock`, a fake `wolf-ism8` session fed with frames:

- Binding from config; fatal cases of §2; fields absent until reported.
- Field ↔ datapoint for every field of §3, by the library's keys; enums both ways.
- Liveness: no session, keepalive close, `noKeepalive` warning, `stale` ⇒ devices stale, replacement keeps values.
- Jump filter: held once, taken on confirmation or after 10 min.
- `SET`: echo answer, field unchanged until reported; equal value not sent; `bad-payload`, `unreachable`, `rateLimited` by interval and by budget; counts survive a restart through KV.
- `temperature-from-ism8i-outdoor`: value, absent ⇒ not reachable.
