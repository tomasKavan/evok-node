# 08 — Onboard driver

## 1. Scope

The controller's own I/O — sections 1..3 — reached over Modbus TCP to `unipitcp`. `unipitcp` already owns the SPI/I2C access to those boards and exposes it over Modbus TCP; a second, independent SPI client would contend with `unipitcp` itself for the same bus. So this driver talks Modbus TCP like everything else that touches this hardware, never SPI directly — the same reason EVOK never speaks SPI either.

Named `onboard` rather than `plc`, because the whole box is the PLC and extensions attach to it — "the PLC driver" would read as covering everything, including 09.

This driver owns transport lifecycle (`open`/`close`) and unit topology only. Binding — turning a resolved definition into live `driver-kit` devices — is [`hw-modbus-kit`](07a-Hw-modbus-kit.md)'s job: this file calls `handshake()` then `bindDefinition()` (07a §9, §12) once per configured unit, and never touches `driver-kit` or a register address directly.

**Must not depend on:** any api, `main`, another driver.

## 2. Configuration

```ts
interface OnboardConfig {
  autogen: boolean;
  transport?: { kind: 'modbus-tcp'; host: string; port: number; timeoutMs?: number };
  rates?: Record<string, number>;               // named rate -> ms; overrides this driver's own defaults
  devices?: { unit: number; definition: string }[];   // present, possibly empty, when autogen is false
}
```

```yaml
drivers:
  PLC:
    type: onboard
    autogen: true                 # main loads /etc/evok-node/autogen.yaml — §3

  PLC2:
    type: onboard
    autogen: false
    transport: { kind: modbus-tcp, host: 127.0.0.1, port: 502 }
    rates: { fast: 100, medium: 500 }
    devices:
      - { unit: 1, definition: modbus/unipi/brain-s107 }
      - { unit: 2, definition: modbus/unipi/e4ai4ao4di5ro }
```

Rules, checked at config-parse time, needing no handshake — the same class as research/13 §Validation:

- **`autogen: true` is exclusive with `transport:` and `devices:`.** Both come from `/etc/evok-node/autogen.yaml` instead (§3); declaring either alongside `autogen: true` is a configuration error, not a precedence rule.
- **`autogen: false` requires `transport:` and `devices:` present.** `devices: []` is legal — a controller with no onboard sections (the Gate) is a normal, not incomplete, configuration; §7 says what that means to a client.
- **`transport.host` is never assumed to be local.** Manual mode is exactly how an operator points this driver at a `unipitcp` reachable over the network rather than the box's own loopback — deliberate, not an oversight. `autogen: true` always resolves to a local endpoint (§4), because it's describing this box's own hardware; reaching a remote one is what manual mode is for.
- **`rates` is independent of `autogen`.** It's operator policy (07a §3's "performance contract"), never a hardware fact, so it stays a plain optional key regardless of which mode supplies the transport and devices. Unspecified names fall back to this driver's own built-in defaults (§8); a name a bound definition's `blocks[].rate` needs, that has neither an override here nor a built-in default, is fatal at `configure()`, naming the missing rate.

## 3. `autogen.yaml`

```yaml
# /etc/evok-node/autogen.yaml — written only by autogen.py (§4), never by hand, never by main or this driver
schema: 1
generatedAt: 2026-09-24T10:03:00Z
generatedBy: run.d                  # run.d | postinst | daemon-fallback — diagnostic only
fingerprint: "sha256:3a1c..."       # hash of the raw facts (product id + CARDS string) that produced this file — what this driver compares at configure() to decide whether regeneration is needed, without re-deriving anything itself
transport:
  kind: modbus-tcp
  host: 127.0.0.1
  port: 502
devices:
  - unit: 1
    definition: modbus/unipi/brain-s107
    boardCode: "00"                 # diagnostic — which table row (§4) matched
  - unit: 2
    definition: modbus/unipi/xs11
    boardCode: "0A"
```

One generator, three callers (research/13 §7) — never three implementations:

| caller | when |
|---|---|
| `run.d` plugin script | `os-configurator` detects a hardware change, early boot |
| `postinst` | install and upgrade, via `dpkg-trigger os-configurator-force` — never `os-configurator -f` directly, which may reboot the machine (ADR-0006) |
| this driver, at `configure()` | file missing, or `fingerprint` stale against currently-readable facts |

All three invoke the same `autogen.py` (§4) as a child process; the third case exists only because `run-parts` fires solely on a detected hardware *change*, so a fresh install with unchanged hardware would otherwise generate nothing, and `postinst` alone cannot always reach the hook directory (§4).

## 4. `autogen.py`

Lives in `packages/hw-definitions`, shipped by the `evok-node-data` package alongside the YAML catalog it reads from (01-Package.md §3.1) — one package, so the script and the catalog it maps into can never drift out of sync with each other. Installed to `/opt/unipi/os-configurator/run.d/61-evok-node-autogen.sh` or the Debian-12-observed `/usr/lib/unipi/run.d`, whichever exists; `postinst` skips silently if neither does — the standalone path (§3's third caller) still works.

What it does, each run:

1. **Reads hardware facts.** Prefers self-read via `/run/unipi-plc/unipi-id/`, falling back to the `unipiid` binary. `/etc/default/unipitcp`'s `LISTEN_PORT`/`LISTEN_IP` are authoritative when present. Shells out to `unipiid card_description.<slot>` per Iris card, since `CARDS` only carries `<code>__<slot>`.
2. **Resolves the family code and board-code table.** The product-id → board-code table (~40 entries) and the family-code map (`1: UNIPI1, 2: Gate, 3: Neuron, 6: CM40, 7: Patron, 15: Iris`) are owned outright here, replacing what evok's `60-evok-autogen.sh` hardcodes.
3. **Emits one `devices:` entry per detected section or card**, each `boardCode` matched against a shipped definition's own `identifies.boardCodes` (research/13 §2).
4. **Resolves the transport endpoint** the same way evok's script does: `127.0.0.1:502` default, or `127.0.0.1:50200` unit 0 for Unipi 1.1.
5. **Writes the file atomically** — temp file plus rename, never a partial write visible to a reader.

Traps deliberately not inherited from `60-evok-autogen.sh`: no string-slicing `UNIPI_PRODUCT_ID` for the family code, no bare `except` that prints "Device not recognized!" and exits 0, no silently dropping an unrecognized card. Any of those situations here is a loud failure instead — non-zero exit, no file written — because a failed `run.d` invocation just leaves the previous `autogen.yaml` in place, which is safe, whereas a silently-wrong one is exactly the wrong-relay failure class research/13 §2.1 exists to catch, just moved one step earlier.

## 5. Model identification and handshake

Fully specified by [07a §9](07a-Hw-modbus-kit.md#9-handshake), §2.1 and §2.2 of research/13; this section only narrates it from this driver's own vantage point, never re-derives it. Every board answers the same identification block at holding 1000–1009. Per configured unit, before `bindDefinition()`:

- `identifies.hardwareId` (register 1004) is the authoritative check where known.
- `census` (registers 1001/1002) is the fallback everywhere else — most of the supported set, since Unipi publishes no hardware-ID table. A definition with a null `hardwareId` is normal, not incomplete.
- Firmware is read first, to select the variant file (closest `minFirmware` floor) that census and identity are then checked against — never the other order.

What §6 covers is what this driver does with a non-`ok` `HandshakeResult` — 07a states the check, not the consequence to a running instance.

## 6. Failure modes

Two distinct classes, deliberately not one:

**Startup-fatal: a `definition` id that doesn't resolve to a shipped or custom file.** Since the catalog and `autogen.py` ship in one package, this only happens on a broken install — a manually deleted YAML file, most likely. Resolution is attempted for every configured or autogen-supplied `definition` at `configure()`, before any transport opens; a failure there rejects `configure()` outright; this driver instance never starts — no partial bind, no degraded unit, the same "never run on hardware it doesn't fully describe" stance research/13 §6 already takes for the corpus as a whole. If this is the only driver configured, the practical effect is that `evok-node` does nothing useful, even though `main` itself keeps running per 02's per-instance failure handling — worth stating plainly rather than implying the whole process exits, since nothing else in `main`'s design (02 §5, §5.1) makes that claim.

**Runtime-degraded, never fatal: a handshake that fails against live hardware.** A census/hardwareId mismatch, or the board being genuinely unreachable — either way the unit's device(s) stay registered, introspection lists them, and any `GET`/`SET` against them answers the existing generic `unreachable` kind (03 §7). No bespoke state machine: this is the same vocabulary every other driver already uses for "the wire didn't answer." Handshake retries in the background, forever, exactly as `driver-onboard/README.md` already states — "a device absent at startup is still registered." Once handshake succeeds, `bindDefinition()` runs and the unit starts answering for real.

The dividing line: a definition failing to *resolve* is a configuration problem, caught before any wire traffic; a definition resolving fine but the live board disagreeing or not answering is a *reachability* problem, and reachability is never grounds to stop the daemon.

## 7. Sections and cardinality

"At most one onboard driver instance" is [14](14-Compat-API.md)'s constraint to define what it *means* to a compat client — this file only obeys it, and does not enforce it in code. `unipitcp` is a fact about the box, not something this driver can see two of; running two onboard instances against it is a configuration mistake, and it's the administrator's responsibility not to make it, the same stance `main` already takes on resource collisions generally (02 §7). One gap worth naming honestly: `main`'s own collision warning compares literal `transport:` keys in config.yaml, so it does not catch two `autogen: true` onboard instances — both would resolve the same host:port only once each reads `autogen.yaml` at `configure()`, after that static check has already run. Not closed by tooling; left as an operational note.

Zero onboard sections (the Gate) is legal — `devices: []`, nothing more to say here that 14 doesn't already own.

## 8. Binding and rates

Delegated entirely to [`hw-modbus-kit`](07a-Hw-modbus-kit.md): this driver opens one `ModbusTransport` per instance, calls `handshake()` then `bindDefinition(def, rates)` once per unit (§2, §5), and holds whatever `BoundDefinition` comes back until `stop()`.

This driver's own built-in `RateTable` defaults — the names the shipped catalog's `blocks[].rate` actually uses — are `{ fast: 100, medium: 500, slow: 5000 }`. Config's `rates:` (§2) only overrides names it names; everything else keeps the built-in value.

## 9. Unipi OS interaction and packaging

Install paths, the two-package split (`evok-node` / `evok-node-data`), and the `run.d`/`postinst` mechanics are [01-Package.md §3](../basics/01-Package.md#3-packaging-and-installation)'s to state and are not repeated here — §3 and §4 above narrate this driver's own use of that mechanism, not the packaging design itself.

One thing genuinely unverified and left that way rather than guessed at: whether `unipitcp` accepts more than one concurrent Modbus TCP client. §7's collision note is the only comment this file makes on that subject.

## 10. Testing

Tier 1 (`design/basics/03-Testing.md`), against the simulator — no hardware:

- Config parse: `autogen: true` with `transport`/`devices` present is rejected; `autogen: false` missing either is rejected; `devices: []` under `autogen: false` is accepted.
- `autogen.yaml` parse: a well-formed fixture loads; a stale `fingerprint` against fixture "current facts" triggers the daemon-fallback invocation of `autogen.py` (§3); a missing file does the same.
- Definition-resolution fatal: a `devices:` entry naming an id with no matching file anywhere (shipped or custom) rejects `configure()`, naming the id — asserted before any `ModbusTransport.open()` call.
- Reachability, not fatal: a fixture unit whose simulator handshake fails (census mismatch) is still listed in introspection; a `GET` against it answers `unreachable`; a later simulator fix that lets handshake succeed brings it to a normal bound state without a restart.
- Rate resolution: a fixture definition naming a `rate` this driver has no built-in default for and no config override for is fatal at `configure()`, naming the rate.
- One full run against a simulated board `00` end to end: `configure()` → `handshake()` → `bindDefinition()` → a `GET`/`SET` round-trip against at least one `unipi.di` and one `unipi.do` channel.
