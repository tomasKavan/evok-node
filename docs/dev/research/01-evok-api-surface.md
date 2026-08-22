# EVOK 3.x API surface — the compatibility contract

Everything here is read from EVOK **3.0.6** source (`47c95c8`) unless marked otherwise.
Where the published docs disagree with the code, **the code is the contract** — real
clients were built against the running service. Discrepancies are listed in §9; they are
the highest-value part of this document.

---

## 1. Transport and routing

Single Tornado HTTP server. Listen address/port from `apis.address` / `apis.port`
(defaults `127.0.0.1:8080`). One app, one port, all protocols. `[V-src]`

| Route (regex as registered) | Handler | Notes |
|---|---|---|
| `/rpc/?` | JSON-RPC 2.0 | POST only |
| `/rest/all/?` | load-all | GET returns a heterogeneous array |
| `/rest/([^/]+)/([^/]+)/?([^/]+)?/?` | REST | `dev` / `circuit` / optional `prop`; POST body is **form-encoded** |
| `/json/all/?` | load-all | identical to `/rest/all` |
| `/json/([^/]+)/([^/]+)/?([^/]+)?/?` | JSON | same semantics; POST body is **JSON** |
| `/bulk/?` | bulk | POST only |
| `/version/?` | version | GET, **`text/plain`-ish** — writes the bare string `v3.0.6` |
| `/ws/?` | WebSocket | only registered when `apis.websocket.enabled: true` |

Consequences of the regex shape that must be reproduced:

- `dev` and `circuit` are **both mandatory** for the REST/JSON device routes. There is no
  `/rest/di` route; "all circuits of a type" is `/rest/di/all` (the literal circuit
  `all`). `[V-src]`
- Trailing slashes are optional everywhere.
- `/rest/all` is matched by its own route *before* the generic one, so `all` is a
  reserved first segment.

### Headers, CORS, OPTIONS

Every REST/JSON/bulk handler sets, unconditionally: `[V-src]`

```
Access-Control-Allow-Origin: *
Access-Control-Allow-Headers: x-requested-with
Access-Control-Allow-Methods: POST, GET, OPTIONS
Content-Type: application/json      (set after the body is written)
```

`OPTIONS` returns **204** with no body. The WebSocket handler's `check_origin` returns
`True` unconditionally, with a comment about Node-RED stripping the scheme. `[V-src]`

### Authentication

**There is none in 3.0.6.** `LoginHandler` / `LogoutHandler` classes exist but are *not
registered in `api_routes`*, and `UserCookieHelper._passwords` / `UserBasicHelper._passwords`
are empty lists, so `get_current_user()` returns `True` for everybody. The only protection
is the default `127.0.0.1` bind plus nginx in front. Open issue **#149** asks for auth.
`[V-src]`

For evok-node: keep the unauthenticated local default (compat) but design the auth hook
in from the start — retrofitting is what upstream is stuck on.

---

## 2. Device types

Canonical type keys, in the registry's iteration order (the numeric ids are legacy and
survive only in the v1.0 alias file format): `[V-src]`

| id | key | id | key |
|---|---|---|---|
| 0 | `ro` | 19 | `watchdog` |
| 1 | `di` | 20 | `register` |
| 2 | `ai` | 24 | `data_point` |
| 3 | `ao` | 26 | `tcp_bus` |
| 5 | `sensor` | 27 | `serial_bus` |
| 8 | `owbus` | 28 | `device_info` |
| 12 | `ds2408` | 29 | `owpower` |
| 15 | `modbus_slave` | 30 | `run` |
| 16 | `board` | 31 | `nv_save` |
| 17 | `do` | 18 | `led` |

**Alternate names** accepted on input and resolved to canonical: `[V-src]`

```
digitalinput → di      digitaloutput → do     relay → ro
input        → di      output        → do     wd    → watchdog
analoginput  → ai      analogoutput  → ao     temp  → sensor
```

Note the asymmetry that bites: alt-names are accepted in **URLs** (resolved via the
registry) but the `dev` field in emitted payloads is always the *canonical* key — except
for 1-Wire sensors, which emit `dev: "temp"` (see §4). `[V-src]`

### Circuit identifiers

Formats, generated at init from the hardware definition (`docs/circuit.md`, confirmed in
`Board.parse_feature_*`): `[V]` `[V-src]`

| Type | Circuit format | Examples |
|---|---|---|
| `ro`, `do`, `di`, `ai`, `ao`, `led`, `watchdog` | `<device_name>_<NN>` | `1_01`, `xS11_02` |
| `owbus`, `owpower`, `nv_save`, `modbus_slave` | `<device_name>` | `1`, `IAQ`, `xS51` |
| `sensor` (`temp`) | 1-Wire address, dots stripped | `2895DCD509000035` |
| `device_info` | model name (grouped) or device name | `L533`, `S167`, `xS51` |
| `data_point` | `<device_name>_<register_address>` | `IAQ_0`, `IAQ_10` |
| `register` | `<device_name>_<register_address>`, plus `_inp` suffix for input registers | `1_0`, `1_1000`, `1_508_inp` |

`<NN>` is 1-based, zero-padded to 2 digits, derived from the feature's `count`.
`<device_name>` is the key under `devices:` in the config — for Unipi controllers that is
the section number (`1`, `2`, `3`).

An **alias** may be used anywhere a circuit is expected: `GET /rest/relay/bedroom_light`.
The v2 `al_` prefix was removed. Resolution checks the type-specific dict first, then the
global alias map, and verifies the aliased device's type matches (canonical or alt-name).
`[V-src]`

---

## 3. REST / JSON semantics

### GET

```
GET /rest/<dev>/<circuit>            → device.full()                      (object)
GET /rest/<dev>/<circuit>/<prop>     → {"<prop>": <getattr(device, prop)>} (object)
GET /rest/<dev>/all                  → [ device.full(), ... ]             (array)
GET /rest/<dev>/all/<prop>           → [ {"circuit": c, "<prop>": v}, ... ]
GET /rest/all                        → [ ... heterogeneous ... ]
```

`prop` is a raw `getattr` on the Python object, rejected only if it starts with `_`. So
`GET /rest/di/1_01/debounce` works, and so does `GET /rest/di/1_01/bitmask` — internal
attributes are exposed. **evok-node should expose an explicit whitelist** derived from the
`full()` shape, and should treat undocumented attribute reads as `404`. `[V-src]`

`/rest/all` enumerates, in this order: `di, ro, do, ai, ao, sensor, led, watchdog,
modbus_slave, owpower, register, data_point, owbus, device_info`. Deliberately excluded:
`nv_save`, `run`, `board`, `tcp_bus`, `serial_bus`, `ds2408`. `[V-src]`

### POST

- `/rest/...` — body is **`application/x-www-form-urlencoded`**; every value arrives as a
  string. This is why so many schema fields accept `["string","number"]`.
- `/json/...` — body is **JSON**.
- The body is validated against a per-type JSON schema (`additionalProperties: false`)
  when a schema exists for that type; unknown properties are rejected. `[V-src]`
- Then `device.set(**kw)` is called and the result wrapped.

Success:

```json
{"success": true, "result": { ...device.full()... }}
```

Failure — **HTTP 404 for every error class**, including schema violations, unknown
properties, out-of-range values and Modbus failures:

```json
{"success": false, "errors": {"<PythonExceptionClassName>": "<str(exception)>"}}
```

`[V-src]` The exception *class name* is part of the observable contract
(`DeviceNotFound`, `ValidationError`, `ModbusException`, `ValueError`, `KeyError`…).
evok-node should emit a compatible envelope while adding a stable machine-readable code
field alongside it (see `05-evok-node-design-notes.md`).

### POST bodies per type (JSON-schema, `additionalProperties: false`)

| `dev` (schema key) | Accepted properties |
|---|---|
| `di` / `input` | `counter` (0…4294967295), `counter_mode`, `debounce`, `mode`, `ds_mode`, `alias` |
| `do` / `output` / `ro` / `relay` | `value`, `mode`, `timeout`, `pwm_freq`, `pwm_duty`, `alias` |
| `ai` / `analoginput` | `mode`, `alias` |
| `ao` / `analogoutput` | `value` (min 0), `mode` ∈ {`Voltage`,`Current`,`Resistance`}, `alias`, `frequency` (Unipi 1.1 only) |
| `led` | `value`, `alias` |
| `watchdog` / `wd` | `value`, `timeout`, `reset`, `nv_save`, `alias` |
| `register` | `value` (0…65535), `alias` |
| `owbus` | `do_scan`, `do_reset`, `interval`, `scan_interval`, `circuit` |
| `owpower` | `value` |
| `sensor` / `temp` / `1wdevice` | `interval`, `alias` |
| `run` | `save` |

Types with **no schema** (validation skipped entirely): `data_point`, `modbus_slave`,
`device_info`, `nv_save`. `[V-src]` Note `modbus_slave.set(print_log=N)` shells out to
`tail -n 255 <logfile>` and returns the raw bytes — an undocumented log-exfiltration
endpoint we should not reproduce as-is.

---

## 4. Payload shapes (`full()`) — exact, per type

These are the wire shapes. Optional keys are marked; `alias` is present **only when
non-empty** on every type. `[V-src]`

```jsonc
// dev: "do"                                   (DigitalOutput)
{ "dev":"do", "circuit":"1_01", "value":0, "pending":false,
  "mode":"Simple", "modes":["Simple","PWM"],
  "pwm_freq":4800.0, "pwm_duty":0,            // only when digital_only
  "alias":"..." }                              // optional

// dev: "ro"                                   (Relay)
{ "dev":"ro", "circuit":"2_01", "value":1, "alias":"..." }

// dev: "di"                                   (DigitalInput)
{ "dev":"di", "circuit":"1_01", "value":0, "debounce":50,
  "counter_modes":["Enabled","Disabled"], "counter_mode":"Enabled", "counter":12345,
  "mode":"Simple", "modes":["Simple","DirectSwitch"],
  "ds_mode":"Simple", "ds_modes":["Simple","Inverted","Toggle"],  // only when mode == DirectSwitch
  "alias":"..." }
// NB: counter is reported as 0 when counter_mode != "Enabled"

// dev: "ai"                                   (AnalogInput)
{ "dev":"ai", "circuit":"1_01", "value":8.703, "unit":"V",
  "mode":"Voltage10", "modes":{ "<name>": {"value":N,"unit":"V","range":[0,10]}, ... },
  "range":[0,10], "alias":"..." }

// dev: "ao"                                   (AnalogOutput — extension/section 2,3)
{ "dev":"ao", "circuit":"2_03", "value":5.9, "unit":"V",
  "mode":"Voltage", "modes":{...}, "range":[0,10], "alias":"..." }

// dev: "ao"                                   (AnalogOutputBrain — section 1 / AOR)
{ "dev":"ao", "circuit":"1_01", "value":8.301, "unit":"V",
  "mode":"Voltage", "modes":{...}, "alias":"..." }
// NB: no "range" key on this variant; value is res_value when mode == Resistance

// dev: "led"                                  (ULED)
{ "dev":"led", "circuit":"1_01", "value":0, "alias":"..." }

// dev: "wd"                                   (Watchdog — note: NOT "watchdog")
{ "dev":"wd", "circuit":"1_01", "value":0, "timeout":2500,
  "was_wd_reset":0, "nv_save":0, "alias":"..." }

// dev: "register"                             (Register)
{ "dev":"register", "circuit":"1_1000", "value":14, "alias":"..." }

// dev: "data_point"                           (DataPoint)
{ "dev":"data_point", "circuit":"IAQ_0", "value":21.5,
  "name":"temperature",                        // optional
  "valid":true,                                // only when valid_mask_reg configured
  "unit":"°C",                                 // optional
  "alias":"..." }

// dev: "owpower"
{ "dev":"owpower", "circuit":"1", "value":true, "alias":"..." }

// dev: "nv_save"
{ "dev":"nv_save", "circuit":"1", "value":0, "alias":"..." }

// dev: "modbus_slave"
{ "dev":"modbus_slave", "circuit":"1", "last_comm":0.084, "slave_id":1,
  "modbus_type":"TCP",                         // "TCP" | "RTU" | "UNKNOWN"
  "modbus_spec":"127.0.0.1",                   // host for TCP, port path for RTU
  "scan_interval":0.02, "alias":"..." }
// last_comm is SECONDS SINCE last successful comm, or 0x7fffffff if never

// dev: "device_info"
{ "dev":"device_info", "circuit":"L533", "family":"Neuron", "model":"L533",
  "sn":0, "board_count":3 }

// dev: "temp"                                 (1-Wire thermometer)
{ "dev":"temp", "circuit":"2895DCD509000035", "address":"28.95DCD5090000.35",
  "value":21.4, "lost":false, "time":1753600000.0, "interval":15,
  "type":"DS18B20", "alias":"..." }

// dev: "1wdevice"                             (DS2438 / multi-value 1-Wire)
{ "dev":"1wdevice", "circuit":"...", "humidity":null, "vdd":4.9, "vad":1.2,
  "temp":21.4, "vis":null, "lost":false, "time":..., "interval":15, "type":"DS2438" }

// dev: "run"                                  (aliases pseudo-device, circuit "alias")
{ "dev":"run", "circuit":"alias", "save":false,
  "aliases": { "my_relay": {"circuit":"ro_1_01", "devtype":"ro"} } }
```

There is also a `simple()` projection (`{dev, circuit, value}`) used internally; it is
**not** reachable over any API in 3.0.6. `[V-src]`

**Cold-start nulls.** Modbus-backed devices initialise `value`, `counter`, `debounce` etc. to
`None` and only populate them on the first successful scan. So between startup and the first
read, `full()` legitimately emits `"value": null` — and after a device goes offline it keeps
emitting the last-read value with no staleness marker. Both are why
R04-23 (staleness in the data model) matters. `[V-src]`

---

## 5. WebSocket

`ws://host:8080/ws`. No subprotocol, no ping/pong, no keepalive, no auth, origin check
disabled. `[V-src]`

### Server → client

- **Unsolicited change events.** On every scan pass that observes changes, one message
  per event batch. With the default filter, the message is `JSON.stringify(device.full())`
  where `device` is a `Proxy` wrapping the changeset — i.e. **an array** for Modbus
  devices but **a bare object** for 1-Wire devices (whose events bypass the proxy).
  This shape inconsistency is the single most-reported client-side breakage. `[V-src]`
- With a non-default filter: always an array, and messages are suppressed entirely when
  nothing in the batch matches.
- Response to `cmd:"all"`: a JSON array of every device's `full()`.
- Response to `cmd:"full"`: the result of `device.full()`.
- **No other command produces a response** — writes are silent. `[V-src]`

### Client → server

```jsonc
{"cmd":"all"}                                        // full state dump
{"cmd":"filter", "devices":["do","ao"]}              // set type filter
{"cmd":"filter", "devices":["default"]}              // reset to default
{"cmd":"filter", "devices":[]}                       // also resets to default
{"cmd":"set", "dev":"do", "circuit":"1_01", "value":1}
{"cmd":"set", "dev":"di", "circuit":"1_01", "debounce":100}   // any kwargs except cmd/dev/circuit/value
{"cmd":"full", "dev":"do", "circuit":"1_01"}         // read one device
```

`cmd` is applied as `getattr(device, cmd)` — **any public method name works**, not just
`set`/`full` (`get`, `set_state`, `get_value`, …). Malformed messages are swallowed
silently with a debug log; there is no error frame. `[V-src]`

`value` semantics: if `value` is an object it is spread as kwargs; if scalar it is the
single positional arg; if absent, all remaining keys become kwargs.

`apis.websocket.all_filtered: true` makes `cmd:all` respect the filter — but the
implementation compares device *dicts* against a list of type *strings*, so it returns an
empty array. Leave `all_filtered` false. `[V-src]`

### Lifecycle traps to fix, not copy

- Clients are stored in a single global `registered_ws["all"]` set **shared with webhook
  handlers**.
- `write_message` is never awaited → unbounded send buffering for slow clients, and write
  errors surface as unretrieved futures.
- When the **last** client disconnects, `stop_scanning()` is called on every Modbus slave;
  for devices configured `scan_enabled: false` this permanently stops hardware polling
  (nothing restarts it on reconnect).
- Filter state is per-connection and lost on reconnect, with no echo of the effective
  subscription.

---

## 6. Webhook

Configured under `apis.webhook`. On every change event, for devices whose `dev` is in
`device_mask`: `[V-src]`

- `complex_events: false` → `GET <address>` with `Content-Type: application/json` and
  **no body**. A bare notification ping.
- `complex_events: true` → `POST <address>` with `Content-Type: application/json` and the
  body being the JSON array of changed devices' `full()` — the same payload as the
  WebSocket.

Code defaults if the key is absent: `address: http://127.0.0.1:80/index.html`,
`device_mask: ["di","sensor","watchdog"]`. Note the **shipped `config.yaml` example uses
`["input","wd"]`**, which matches nothing because the comparison is against canonical
names (`di`, `watchdog`). `[V-src]`

Delivery is fire-and-forget (`fetch` never awaited), unbounded, no retry, no timeout, no
circuit breaker. 1-Wire events raise a `TypeError` inside the handler (dict iterated as a
list) which is swallowed upstream, so **webhooks never fire for 1-Wire sensors**. `[V-src]`

---

## 7. Bulk

`POST /bulk`. Three optional top-level keys, processed in order. Always HTTP 200; errors
come back as `{"success": false, "errors": {...}}`. `[V-src]`

```jsonc
{
  "individual_assignments": [
    { "device_type": "do", "device_circuit": "1_01", "assigned_values": {"value": 1} }
  ],
  "group_queries": [
    { "device_types": ["do","ro"], "group": 1,
      "device_circuits": ["1_01"], "global_device_id": 2 }
  ],
  "group_assignments": [
    { "device_type": "do", "group": 1, "device_circuits": ["1_01"],
      "assigned_values": {"value": 1} }
  ]
}
```

Response mirrors the request keys:
`{"individual_assignments":[ ...full()... ], "group_queries":[[...]], "group_assignments":[[...]]}`.

**Only `individual_assignments` actually works in 3.0.6.** `group_queries` and
`group_assignments` build Python `map` objects and hand them to `json.dumps`, which raises
`TypeError: Object of type map is not JSON serializable`; `group_assignments` additionally
indexes a `dict_values` with a device object. Both therefore return the error envelope.
`global_device_id` filters on `single_dev.dev_id`, an attribute no device class defines.
`[V-src]` — this is inference from reading the code paths, but the failure is
deterministic and easy to confirm on a device.

Implement `group_*` as documented (they were presumably functional in v2). Don't repeat broken behavior.

---

## 8. JSON-RPC

`POST /rpc`, JSON-RPC 2.0 (`tornado-jsonrpc2`). Params may be positional or named.
`DeviceNotFound` maps to *Invalid params*. `[V-src]`

Methods **actually defined** in 3.0.6:

```
input_get(circuit)              → (value, debounce)
input_get_value(circuit)        → value
input_set(circuit, debounce)
relay_get(circuit)              → value
relay_set(circuit, value)       async
output_get(circuit)             → value
output_set(circuit, value)      async
output_set_for_time(circuit, value, timeout)   async, timeout must be > 0
ai_get(circuit)                 → full()
ai_set_bits(circuit, bits) | ai_set_interval(...) | ai_set_gain(...) | ai_set(circuit, bits, gain, interval)
ao_set_value(circuit, value)    async
ao_set(circuit, value, frequency)  async
owbus_get(circuit) | owbus_set(circuit, scan_interval) | owbus_scan(circuit) | owbus_list(circuit)
sensor_get(circuit) | sensor_get_value(circuit) | sensor_set(circuit, interval)
```

Caveats found by reading it: `[V-src]`

- **The published docs are wrong.** `docs/apis/rpc.md` demonstrates `di_get` and `do_set`;
  neither exists. The real names are `input_get` / `output_set`. evok-node should
  implement **both** spellings.
- `ai_set_bits`, `ai_set_gain`, `ai_set` pass kwargs (`bits`, `gain`, `interval`) that
  `AnalogInput.set()` does not accept → `TypeError`. Dead v1-era surface.
- Several non-`async def` methods return un-awaited coroutines (`input_set`,
  `sensor_set`, …) because awaitability is tested on the *method*, not the result. They
  will fail to serialise.
- The Basic-auth path calls `base64.decodestring`, removed in Python 3.9 — it would crash
  if passwords were ever configured.

Treat JSON-RPC as a legacy compatibility shim: implement the method names, make them all
work, keep the response shapes.

---

## 9. Doc↔code discrepancies (compat decisions required)

| # | Docs / examples say | Code 3.0.6 does | Recommendation |
|---|---|---|---|
| 1 | Payload examples include `glob_dev_id` (and `relay_type` for relays) | **Neither field is emitted.** `glob_dev_id` survives only as the non-existent `dev_id` attribute in bulk filtering | Omit by default; consider a `compat.emitGlobDevId` flag if a real client needs it |
| 2 | RPC methods `di_get`, `do_set` | `input_get`, `output_set` | Implement both |
| 3 | Alias file at `/var/lib/evok/aliases.yaml` | `/var/lib/evok/alias.yaml` (singular) | Read both, write the singular form |
| 4 | `GET /rest/run/alias` returns `{"my_relay": "relay_1_01"}` | returns `{"my_relay": {"circuit":"ro_1_01","devtype":"ro"}}` | Follow the code |
| 5 | 1-Wire bus configured with `type: OWBUS` | the bus factory matches `'OWFS'`; `'OWBUS'` creates nothing | Accept both spellings |
| 6 | Manually-defined 1-Wire sensors under `devices:` | doubly broken: the bus factory branches on `'OWFS'` while the static-device branch inside the same loop branches on `'OWBUS'`, so the two can never both match; and the device branch calls `device_data.getintdef(...)` on a plain dict → `AttributeError` | Implement properly |
| 7 | `hw_definitions` DI example uses `direct_reg: 1016, polar_reg: 1017, toggle_reg: 1018` | real xS51 map has 1014/1015/1016 | Doc examples are composites — trust shipped definitions |
| 8 | `webhook.device_mask: ["input","wd"]` (shipped config) | compared against canonical `di`/`watchdog` → matches nothing | Normalise alt-names at config parse |
| 9 | WS `cmd:all` "returns a list" | returns an object for the `full` command and for 1-Wire events | Always emit an array; offer a legacy flag |
| 10 | `/version` documented as an API endpoint | returns a **bare string**, not JSON | Keep byte-compatible; add `/version.json` if we want structure |
| 11 | Bulk `group_queries` / `group_assignments` | raise `TypeError` during serialisation | Implement correctly |
| 12 | `register` device type is documented | `parse_feature_register` never registers the device as eventable → no WS/webhook updates (issue #214); maintainer says "not supported anymore" | Implement fully, emit events |

---

## 10. Compatibility test strategy

The cheapest way to be certain: build a **golden-transcript** test suite.

1. Capture, from a real Unipi controller running EVOK 3.0.6, the full response to
   `GET /rest/all`, `GET /rest/<dev>/<circuit>` for every type, a WS session transcript,
   and a webhook capture. Store as fixtures.
2. Replay against evok-node with a simulated Modbus slave seeded to the same register
   values; assert JSON deep-equality modulo a documented allowlist of intentional
   differences (§9).
3. Keep `docs/apis/Evok_API_OAS.yaml` from upstream as a schema oracle — validate our
   responses against it in CI, and record every place we deliberately diverge.
4. Run the upstream `examples/test_{rest,json,bulk,rpc,websocket,webhook}.py` scripts
   against evok-node unmodified. They are small and make excellent acceptance tests.
