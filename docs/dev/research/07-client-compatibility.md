# Client compatibility — what must be byte-compatible

Decision: **Node-RED and Home Assistant integrations are the compatibility baseline.** This
document is the result of reading the source of every known EVOK client, so we know exactly
which surface is load-bearing and which is free.

All claims verified by reading cloned source unless marked *(inferred)*.

---

## 1. Landscape — three corrections to our assumptions

1. **There is no core Home Assistant integration for Unipi/EVOK**, and `marko2276/ha-unipi-neuron`
   is not in the HACS default list either. The "HA baseline" is one 23-star custom component,
   manually installed. It is actively maintained (last commit 2026-02-01).
2. **The Node-RED baseline is Unipi's own package**, not `phillipsnick`'s:
   `@unipitechnology/node-red-contrib-unipi-evok` (274 dl/month, vendor-published, last commit
   2024-08-07) vs `node-red-contrib-unipi-evok` (15 dl/month, dead since 2017).
3. **Two clients newer than our original list exist and matter more**:
   `matthijsberg/unipi-homeassistant` (2025, EVOK→MQTT-Discovery bridge, the most
   EVOK-3-native client and the only consumer of `/json/` and of the `modes`/`range`/`unit`
   metadata) and `blackbit-consulting/unipi-mqtt-ng` (TypeScript, Feb 2026 — and written
   against EVOK **2** names, so completely broken on EVOK 3).

Clients read: `@unipitechnology/node-red-contrib-unipi-evok`, `phillipsnick/node-red-contrib-unipi-evok`
(+ its pinned `unipi-evok@0.1.0`), `marko2276/ha-unipi-neuron` (+ `evok-ws-client==0.0.4`),
`matthijsberg/unipi-homeassistant`, `matthijsberg/unipi-mqtt`, `mhemeryck/evok2mqtt`,
`mwittig/pimatic-unipi-evok`, `blackbit-consulting/unipi-mqtt-ng`, and the vendor web UI
`UniPiTechnology/evok-web-jq`.

---

## 2. MUST be byte-compatible

| # | Surface | Requirement | Breaks if changed |
|---|---|---|---|
| 1 | `/ws` reachable on **:8080 and :80** | Path `/ws`, no subprotocol, no auth | All 8 clients. Port 80 specifically: HA's `evok-ws-client` hardcodes `"ws://" + ip + "/ws"` with **no port option** |
| 2 | **WS events are always JSON arrays**, including 1-Wire | Never emit a bare object | **HA crashes** (uncaught `AttributeError` on `str.keys()`); **phillipsnick takes down the whole Node-RED process** (issue #8); evok2mqtt raises `KeyError: 0`. Fixing this *repairs* two clients broken today |
| 3 | Default (no-filter) connection streams all change events | No `cmd:filter` needed to receive data | evok2mqtt, pimatic, web UI, unipi-mqtt-ng — none of them ever filter |
| 4 | Filtered subscriptions always yield arrays; suppressed when empty | | HA — this is the only thing keeping #2 from killing it today |
| 5 | `{"cmd":"all"}` → array of every device's full state | Sent **once at connect**, not as a heartbeat | HA, Unipi NR nodes, unipi-mqtt-ng |
| 6 | `cmd:filter` accepts **canonical AND legacy names in one array**, ignoring unknowns | HA sends `["relay","led","input","ro","do","di"]` | HA, Unipi v2 NR node |
| 7 | `cmd:set` `dev` accepts alt-names: `relay`→`ro`, `input`→`di`, `output`→`do`, `analogoutput`→`ao`, `temp`→`sensor`, `wd`→`watchdog` | | HA, evok2mqtt (`relay`,`output`), Unipi v2 NR node, unipi-mqtt |
| 8 | `value` accepts int, `"1"`/`"0"` strings, floats, **and objects spread as kwargs** | HA PWM lights send `{"pwm_duty":"50"}` | HA, phillipsnick (strings), unipi-mqtt (floats) |
| 9 | **Emitted `value` is a JSON number** (`1`/`0`) — never a string or boolean | | HA, evok2mqtt, pimatic all compare `value == 1` and fail **silently** |
| 10 | Event fields `dev`, `circuit`, `value` always present | | Every client |
| 11 | **Malformed / non-JSON WS frames silently ignored, connection kept open** | pimatic sends the literal string `" "` every 20 s as a heartbeat | pimatic. Easy to break in a Node impl that validates and closes |
| 12 | RFC6455 **ping → pong**, no long silences | unipi-mqtt uses `ping_timeout=8`, matthijsberg-HA `10`, and nginx has `proxy_read_timeout 180` on `/ws` | unipi-mqtt, matthijsberg-HA, HA |
| 13 | Tolerate rapid connect/disconnect churn; **never stop polling when the last client leaves** | | evok2mqtt opens a **new WS connection per set command**. EVOK's `stop_scanning()`-on-last-disconnect must not be reproduced |
| 14 | `GET /rest/all` → JSON **array**, HTTP **200** | | phillipsnick (rejects ≠200), pimatic (rejects non-array), web UI |
| 15 | `GET /rest/{dev}/{circuit}[/]`, alt-names in path, trailing slash optional | `relay`,`input`,`analoginput`,`analogoutput`,`sensor`,`temp`,`output` | pimatic, unipi-mqtt, web UI |
| 16 | `POST /rest/{dev}/{circuit}` accepting **form-urlencoded**, returning `{"success":true,…}`, **non-2xx on error** | Both the `success` field *and* the status code are load-bearing, by different clients | pimatic reads `success`; unipi-mqtt requires exactly 200; web UI uses jQuery `error:` on non-2xx |
| 17 | `GET /json/all`, `/json/{dev}/{circuit}`, `/json/{dev}/{circuit}/value` | | matthijsberg-HA — the only `/json/` consumer |
| 18 | `modes` (nested `range`, `unit`), `mode`, `counter`, `counter_mode`, `counter_modes`, `ds_mode`, `ds_modes`, `alias` | | matthijsberg-HA reads `modes/range/unit` to build HA entity min/max; web UI reads all |
| 19 | `dev:"device_info"` in `/rest/all` and `GET /rest/device_info/{circuit}` | | matthijsberg-HA, web UI |
| 20 | **`dev:"temp"`** for 1-Wire temperature — the one place EVOK emits an alt-name | | pimatic, Unipi NR v3, matthijsberg-HA |
| 21 | Circuit format `<name>_<NN>`; 1-Wire = bare ROM id; `UART_<n>_<N>_<NN>` | Hardcoded in HA's three regexes and Unipi's NR `.`→`_` normaliser | HA, Unipi NR nodes |
| 22 | `POST /rest/run/alias` `{save:1}`, `POST /rest/wd/{circuit}` `{nv_save:1}` | | vendor web UI |

**#9 deserves emphasis.** Three independent clients compare the emitted `value` to the integer
`1` and fail *silently* if it's a string or boolean — while HA and pimatic *write* `"1"` as a
string. So: **strict integers on the read side, liberal on the write side.** This asymmetry is
the single easiest thing to get wrong.

---

## 3. Free to change — no client uses it

| Surface | Evidence |
|---|---|
| `glob_dev_id`, `pending` | **Zero hits** across all 8 clients + 2 protocol libs + web UI |
| `relay_type` | Only in `phillipsnick/unipi-evok`, already dead on EVOK 3 for other reasons |
| `/bulk` (all three forms) | No client uses it → implement `group_*` correctly |
| `/rpc` | No client uses it |
| `/version` | Proxied by nginx, fetched by nobody |
| Webhooks | No client uses them |
| `{"cmd":"full",…}` | No client sends it |
| **Arbitrary-method WS dispatch** (`getattr(device, cmd)`) | No client sends anything but `all`, `filter`, `set`. **Close this hole.** |
| `GET /rest/{dev}/all` and `/rest/{dev}/all/{prop}` | Unused |
| `GET /…/{circuit}/{prop}` as raw `getattr` | Only `/value` is used → whitelist the rest as planned |
| `errors.__all__` | Only pimatic looks for it and already gets `undefined` on EVOK 3, falling back to `"failed"`. Our typed error object is safe |
| `apis.websocket.all_filtered` | Broken upstream, nobody relies on it |
| Per-connection filter state lost on reconnect | Every client re-handshakes from scratch. Adding a subscription echo is safe |

### Two *improvements* that are strictly free wins

- **`{"cmd":"filter","devices":["default"]}` is a no-op in EVOK 3.0.6** — `"default"` is in
  neither the canonical nor the alt-name table, so the list ends empty and the code raises,
  leaving the filter unchanged. **Unipi's own v3 Node-RED node sends exactly this** when the
  user disables filtering. Making it actually reset the filter fixes the vendor's node.
- **Accepting the v2 `al_<alias>` prefix as an input alias.** EVOK 3 removed it, but Unipi's
  own v3 NR node still builds `al_<alias>` and puts it in the `circuit` field — so aliased set
  commands from the vendor's own node silently do nothing. Accepting both spellings costs one
  line and repairs it.

---

## 4. ⚠ One constraint that limits event batching

`mhemeryck/evok2mqtt` does `obj = json.loads(payload)[0]` — it **hard-indexes element 0**. If a
message batches N devices, N−1 are silently dropped.

So "coalesce a whole scan pass into one array" breaks evok2mqtt, even though it satisfies
requirement #2. Every other client handles arbitrary array lengths.

**Recommendation:** default to **one device per event frame** (array of length 1) to stay
compatible, and make batching an opt-in config knob for clients that can use it. Note that
EVOK itself batches — its `Proxy` wraps the whole changeset — so evok2mqtt is *already* lossy
against real EVOK. Matching EVOK's batching is defensible; defaulting to unbatched is
strictly better for that client and costs only WS frame overhead.

---

## 5. Deployment requirement: the :80 reverse proxy

Four clients hardcode or default to port 80 (`ha-unipi-neuron`, `evok2mqtt`, `pimatic`, web UI
via `location.port`). This works today only because Unipi OS ships nginx in front —
`evok-web-jq/nginx-site.conf` listens on `:80` and proxies `/ws`, `/rest`, `/json`, `/bulk`,
`/rpc`, `/version` to `127.0.0.1:8080`, with `proxy_read_timeout 180` on `/ws`.

**Without an equivalent, `ha-unipi-neuron` — our stated HA baseline — cannot be configured at
all**, because `evok-ws-client` offers no port option.

**Decision: keep nginx.** We do not ship a built-in `:80` listener. evok-node listens on
`:8080` exactly as EVOK does, and nginx in front is a documented deployment requirement.

Consequences to handle:

- Ship a **reference nginx site file** (derived from `evok-web-jq/nginx-site.conf`) in the
  package and reference it in the install docs, so a from-scratch install isn't guesswork.
  If the stock `evok` nginx site is already present, it works unchanged — our port and paths
  match.
- **`proxy_read_timeout 180` on `/ws` is load-bearing.** Our WebSocket must produce traffic —
  a protocol ping is enough — comfortably inside 180 s, or nginx silently drops idle
  connections. Combined with client requirements (`unipi-mqtt` needs a pong within 8 s), the
  safe design is a server-initiated ping every ~20 s plus prompt pong replies.
- Nginx buffers by default. If our event rate is high, `proxy_buffering off` on `/ws` matters
  for latency; verify against the reference config.
- An **integration test must run through nginx**, not just against `:8080` directly — the
  HA baseline only ever talks to the proxy, so a proxy-only failure would be invisible in
  direct tests.

---

## 6. Clients we cannot fix by conforming to EVOK 3

Three are broken purely because they use v2 device names, and conforming to EVOK 3 keeps them
broken:

| Client | What's broken | Cause |
|---|---|---|
| `pimatic-unipi-evok` | relays and DIs never update; discovery misses them | registers `relay`/`input`, EVOK 3 emits `ro`/`di` |
| `phillipsnick/node-red-contrib-unipi-evok` | everything | reads `input`/`relay` + `relay_type` |
| `unipi-mqtt-ng` (Feb 2026!) | everything | reads `relay`/`input`, and gates all output on a `dev:"neuron"` message that EVOK 3 never emits |

Fixing them would require deliberately being **more** backward-compatible than EVOK 3 —
emitting `dev:"relay"`, `relay_type` and `dev:"neuron"`. That conflicts with every other
client, so it can only be an **opt-in per-connection legacy mode**, not a default.

Worth noting that a brand-new client was still written against EVOK 2 names in **February
2026**, which is an argument for keeping alt-name *acceptance* permanently even though we
don't emit them.

---

## 7. Consequences for our `compat` flags

Given the above, the flag set reduces to:

```yaml
compat:
  wsAlwaysArray: true      # ALWAYS keep true — it repairs HA + phillipsnick. Flag exists only
                           # to reproduce EVOK's object/array inconsistency for A/B testing.
  legacyErrorStatus: true  # non-2xx on error. Required by unipi-mqtt (needs exactly 200)
                           # and the vendor web UI (jQuery error: callback).
  batchEvents: false       # false = one device per frame (protects evok2mqtt).
  acceptAliasPrefix: true  # accept v2 `al_<alias>` on input. Repairs Unipi's own v3 NR node.
  emitLegacyDevNames: false  # opt-in only; would need relay_type and dev:"neuron" too.
```

`emitGlobDevId` is dropped — no client reads it, and v2 compatibility isn't required.

**Note that `legacyErrorStatus: true` is not merely legacy** — it is a live requirement, since
`unipi-mqtt` checks `status_code == 200` and ignores `success` entirely, while pimatic does the
opposite. Both the status code and the `success` field must be correct.
