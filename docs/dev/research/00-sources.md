# Sources

## Primary — upstream implementation

| Source | Notes |
|---|---|
| https://github.com/UniPiTechnology/evok | The reference implementation. Read at `47c95c8` (main, 2025-09-02). Latest tag **3.0.6**. History: 1045 commits, 2016 → 2025. |
| https://github.com/UniPiTechnology/evok-web-jq | Demo web UI (jQuery Mobile). Thin client; only touches `/rest/all`, `/rest/wd`, `/rest/run`, `/rest/device_info` plus the WebSocket. Useful mainly as proof of which fields real clients depend on. |
| https://github.com/UniPiTechnology/unipi-tools | `fwspi`, `fwserial`, `fwi2c`, `unipitcp`, `libunipichannel.so`. Establishes that the internal CPU↔coprocessor link is SPI and that EVOK never touches it directly. |
| https://github.com/martyy665/pymodbus/commit/566cd7d | The single-commit fork EVOK pins for the "TID overflow" fix. See `04-known-bugs-and-lessons.md` §1. |

**Source layout** (EVOK 3.0.6, ~4000 LoC total):

```
evok/evok.py           548   Tornado app, routes, WS/webhook handlers, bulk handler, main()
evok/modbus_slave.py  1743   Everything: cache map, slave, board, and every device class
evok/config.py         320   config.yaml + hw_definitions + aliases loading, device factory
evok/owdevice.py       398   1-Wire via asyncowfs
evok/devices.py        329   Device registry, devtype constants, alias store
evok/schemas.py        239   JSON-schema for POST bodies (per device type)
evok/rpc_handler.py    184   JSON-RPC method surface
evok/handlers_base.py   93   Shared REST/JSON GET+POST logic
evok/modbus_unipi.py    75   pymodbus client wrappers (RTU/TCP)
evok/devents.py         45   Global status/config callback dispatch
evok/errors.py          10
```

**Docs in-repo** (`docs/`, published to readthedocs via mkdocs):
`index.md`, `installation.md`, `apis.md`, `circuit.md`, `debugging.md`,
`configs/{evok_configuration,aliases,hw_definitions}.md`,
`apis/{rest,json,websocket,bulk,webhook,rpc}.md`,
`apis/Evok_API_OAS.yaml` (3879 lines — the fullest formal API description).

## Documentation

| URL | Value |
|---|---|
| https://evok.readthedocs.io/en/stable/ | Same content as `docs/` in the repo. Prefer the repo copy — it is versioned with the code. |
| https://unipitechnology.stoplight.io/docs/evok | Rendered OpenAPI. The in-repo `docs/apis/Evok_API_OAS.yaml` is the same spec and is diffable. |
| https://kb.unipi.technology/en:00-start | KB root. |
| https://kb.unipi.technology/en:sw:02-apis | API overview: EVOK vs Modbus TCP vs sysfs vs unipiid. |
| https://kb.unipi.technology/en:sw:02-apis:02-modbus-tcp | **Key page.** How `unipitcp` exposes the boards on `127.0.0.1:502`, unit-id = section number. |
| https://kb.unipi.technology/en:sw:02-apis:04-sysfs | Per-section sysfs tree under `/run/unipi-plc/by-sys/`. Board name/serial/firmware, AI/AO modes, MWD, ULED. |
| https://kb.unipi.technology/en:sw:02-apis:05-unipiid | `unipiid` identity API. Debian 13+ only. The authoritative host-side identity source. |
| https://kb.unipi.technology/en:sw:04-unipi-firmware:05-update-firmware | Firmware flashing, `fwspi -u <section>`, FW 5.x→6.x upgrade caveat. |
| https://kb.unipi.technology/en:hw:007-patron (+ `:portmap`, `:downloads`, `:description-of-io`, `:technical-parameters`) | Patron. |
| https://kb.unipi.technology/en:hw:02-neuron (+ same subpages) | Neuron. |
| https://kb.unipi.technology/en:hw:01-axon (+ same) | Axon — **discontinued**, no further SW updates. |
| https://kb.unipi.technology/en:hw:004-edge (+ `:02-description-of-io`, `:06-peripherals`, `:11-technical-parameters`) | Edge. Full model table is text (readable). |
| https://kb.unipi.technology/en:hw:025-gate | Gate. No local I/O. |
| https://kb.unipi.technology/en:hw:03-unipi11 | Unipi 1.1 / Lite. GPIO+I²C, `unipi-one-modbus` on port **50200**. |
| https://kb.unipi.technology/en:hw:04-extensions (+ `:communication-and-addressing-of-module`, `:01-first-steps`, `:downloads`, `:technical-parameters`) | Extensions, DIP switches, RS-485 defaults. |
| https://kb.unipi.technology/en:automation:mwd-hidden | Master watchdog semantics, incl. the FW 6.26→6.28 behaviour change. |

## Register maps — ✅ now in the repo

**`docs/modbus-reg-map/`** holds the official maps for Neuron (14 models), Patron (10),
Axon (18), Extensions, Edge (4) and Unipi 1.1 / Lite. This is the ground truth for
per-model register layout; see [`06-register-maps.md`](06-register-maps.md) for the
inventory, the CSV schema, and the gaps it closed (unit-0 addressing formula, PLC
identification block, storage-life registers, the >16-channel bug) plus **one correction**
to the earlier notes (register 1002 bit layout was reversed).

A derived per-model I/O census is generated at `docs/research/derived/model-io-census.csv`.

Also worth pulling from a real device rather than from documentation:
`/etc/evok/hw_definitions/*.yaml` — the shipped definitions are more trustworthy than the
doc examples (which are illustrative composites that match no real board; see
`03-config-and-hw-definitions.md`).

## Community — bug and failure-mode evidence

- GitHub issues: 153 total (27 open / 126 closed) at time of research. High-value open
  issues, essentially a maintainer-authored to-do list: **#164** async init, **#192**
  hot-plug, **#153** per-device TCP session, **#201** validity flag + timestamp, **#74**
  bus contention, **#131** address-conflict detection, **#209**/**#195** >16-channel
  addressing, **#210** RS485 instability, **#149** authentication.
- Pull requests: **#215** (register WS updates), **#193** (rework init, draft),
  **#154** (TCP session per device).
- `forum.unipi.technology` topics 99, 400, 500, 513, 516, 519, 545, 557, 558, 585, 753,
  772, 965, 1042, 1276, 1351, 1360, 1404, 1436.
- Third-party clients whose bug trackers document the API's instability:
  `phillipsnick/node-red-contrib-unipi-evok#8`, `mwittig/pimatic-unipi-evok#12`,
  `marko2276/ha-unipi-neuron`, `mhemeryck/evok2mqtt`, `matthijsberg/unipi-mqtt`.

## Known gaps

Carry these forward; do not paper over them with guesses:

1. PLC (Patron/Neuron/Axon/Edge) Modbus register maps — XLSX only, not yet read.
2. Edge part-number decoder — PNG only. Do not write a part-number parser from inference.
3. `platform_family` numeric IDs published only for Edge (6) and Patron (7).
4. `ForceOutput` register (needed to write a DO that DirectSwitch has claimed) — address
   not published anywhere.
5. Storage-life register addresses — names documented, addresses not.
6. Modbus RTU inter-frame / timeout guidance — the KB gives none. Derive t1.5/t3.5 from
   baud rate per the Modbus spec.
7. Extension baud-rate register encoding — only `14 = 19200` is directly verified; the
   rest of the table is ordered inference.
8. Unipi 1.1 Modbus unit-id and register map — undocumented on readable pages.
