# Capture trip runbook

**One session, unrecoverable if skipped.** Everything here must be recorded from stock EVOK 3.0.6
*before* anything replaces or removes it. After that, no amount of work recreates it — these are
measurements of a system that will no longer exist.

Scheduled: week of 2026-08-10. Units: **L527** (do this one first — 3 sections, both AI
abstractions, the 16-DI boundary in one dump), **M527 #1**, **S167-LTE**, and **the Gate if it
runs stock EVOK** (zero local I/O is a named requirement in research/09 §2: an empty device tree
must serve an empty API, not an erroring one — and that payload is as unrecoverable as the others).
All confirmed stock and on Debian 13 as of 2026-08-10. Extensions on hand: **xS11** and **xG18**;
the xS51 and the second M527 are approved but not yet ordered.

Blocks: N1 golden tests, all of N9, the migration tool's golden fixtures, and ADR-0002's
dependency list. **The compat surface moving to N9 does not make this less urgent** — it only moves
when the transcripts are consumed, and they cease to exist the moment EVOK leaves these units.

## The four rules

1. **Capture before you change anything.** Not one `systemctl stop`, not one config edit, until
   phases 1–2 are done and the tarball is off the unit.
2. **Never `apt purge evok`.** `apt remove` keeps `/etc/evok/*` (conffiles) and
   `/var/lib/evok/alias.yaml`; purge destroys both, and those are the migration tool's only real
   inputs. Migrate before purging, on every unit, forever.
3. **The `start_index` baseline needs EVOK installed** (phase 5, L527 only). Once ADR-0002's
   `Conflicts: evok` lands, getting it back means reinstalling EVOK. Do it while it is already
   there.
4. **An empty transcript is not a fixture.** WS and webhook captures with no events in them
   record nothing. Make inputs change while they run.

Two phases write to a unit, and both restore what they touched: **phase 4** edits
`/etc/evok/config.yaml`, **phase 5** edits a file in `/etc/evok/hw_definitions/`. Phase 1 with
`CAPTURE_WRITES=1` also writes — to a ULED, deliberately. Everything else reads.

## Phase 0 — before you leave

- [ ] `tools/capture/capture.sh` and `tools/capture/capture-events.py` somewhere you can reach
      from the units.
- [ ] Laptop on the same network segment, its IP noted — the webhook receiver runs on the laptop,
      so EVOK has to be able to reach it.
- [ ] A DI you can toggle by hand on each unit, a DS18B20 you can warm with your hand, and on the
      L527 a relay wired to a DI **on a different section**. Without changing inputs, phases 3–5
      produce empty files.
- [ ] Disk space for the tarballs. Size is unknown — the api directory is ~200 small files per
      unit, the journal dumps dominate.

## Phase 1 — automated collection, per unit

```sh
scp tools/capture/capture.sh root@<unit>:/tmp/
ssh root@<unit> 'CAPTURE_WRITES=1 bash /tmp/capture.sh'
scp root@<unit>:/tmp/evok-capture-*.tar.gz ./
```

`CAPTURE_WRITES=1` adds section 6e: a ULED set to 1 and back to 0, one deliberately invalid
value, and one bulk `individual_assignments`. That is the only way to capture the **write-side
envelopes** — and the error envelope leaks the Python exception *class name*
(`{"success":false,"errors":{"<ClassName>":…}}`), which real clients key off. Drop the flag if you
would rather not write at all, but the envelopes are then lost permanently.

Runtime is dominated by the 60 s idle-CPU sample and 400 latency curls. It collects, in one pass:

| Group | What | Why it matters |
|---|---|---|
| identity | `/etc/os-release`, `unipiid`, `/run/unipi-plc/unipi-id/*`, sysfs `/run/unipi-plc/by-sys/iogroup[1-3]/{sys_board_name,sys_board_serial,firmware_version,ow_power_off,master_watchdog_*}` | The identity provider chain forks on Debian generation. Capture **both** paths on every unit even though all four have `unipiid`, so the Debian 12 branch has real data to test against. The *absence* of `ow_power_off` on 13 is itself the fact |
| packaging | `apt-cache show evok`, `dpkg -L evok`, `dpkg -s evok`, conffiles, `systemctl cat evok unipitcp`, `apt-mark showmanual`, `nginx -T`, `/etc/nginx/sites-available/evok` | ADR-0002's `Conflicts:`/`Depends:`/`Replaces:` set cannot be written without it. Two nginx sites claiming `default_server` means nginx will not reload |
| config | `/etc/evok/{config.yaml,autogen.yaml,hw_definitions/}`, `/var/lib/evok/alias.yaml`, `/etc/default/unipitcp`, `/etc/unipi-one-modbus.d/` | Migration golden fixtures (ADR-0003). Shipped `hw_definitions` are more trustworthy than the published doc examples — the DI example's `direct_reg: 1016` contradicts the real xS51 map's 1014 |
| firmware | `fwspi -u 1..3`, plus registers 1000 (firmware version), 1003 (firmware id), 1004 (hardware id), 1001/1002 (I/O census), 1005/1006 (serial) per unit id | FW 5.x boards may not match the register maps at all. And if any unit predates **6.28**, the MWD behaviour fork is observable — in which case **do not upgrade that unit's firmware** |
| api | `/version`, `/rest/all`, `/json/all`, `/rest/<type>/all` and `/json/<type>/all` for all 14 enumerated types *and* the 6 excluded ones, all 8 alt-names, single-circuit GETs, `/rest/…/value` and `/json/…/value`, error shapes, `OPTIONS`, CORS headers, read-only `/bulk` and `/rpc` calls, and `/version` + `/rest/all` + `/json/all` again through nginx on `:80` | The compatibility contract. Response *headers* are part of it, so they are saved alongside every body |
| baseline | idle CPU over 60 s, p50/p95/p99 of `/rest/all` and of a single-circuit GET, `journalctl -u evok`, `/run/unipi_stats/*` | Finding 4.5's comparison target **is this capture** — the ~16.6 % idle-CPU figure in the bug archaeology was measured on an RPi 3B+ Neuron with one board, not on an i.MX 8M Mini Patron, so it is not this unit's baseline |

The `/rest/register/<unit>_<addr>` reads will partly fail, by design. A `register` device exists
only where a definition declares a `REGISTER` feature, and reads come from the per-slave scan
cache — an address nothing polls raises `ENoCacheRegister`. EVOK's real bands are roughly holding
`0…35` and `1000…1030`. **The misses are data**: they map what is reachable through the API versus
what needs a direct Modbus read to `127.0.0.1:502`.

Check the tail of the run. `missing.txt` lists everything it could not find — `fwspi` absent means
`unipi-firmware6` isn't installed and firmware identity has to come from the register reads.

The `/bulk` `group_queries` call is expected to come back as an error envelope (`map` is not JSON
serialisable in 3.0.6). Capture it anyway: we need to know exactly what it says before deciding
whether to reproduce or fix it.

## Phase 2 — sanity check the tarball, on the spot

Before moving to the next unit:

- [ ] `api/rest_all.json` is a non-trivial array, not `[]` or an error. On the **Gate**, an empty
      or odd array is the expected result and is the fixture — note what it actually did.
- [ ] `config/config.yaml` and `config/hw_definitions/` exist.
- [ ] `config/alias.yaml` exists, and `config/alias-yaml-raw.txt` shows its `version:` line
      verbatim. Both `1.0` (list shape, numeric `dev_type`) and `2.0` (map shape, `devtype`) load,
      quoted or not — the code compares against both the string and the raw value in different
      places. Only an **other or missing** version makes EVOK silently ignore the whole file and
      return `{}`. If a unit has one of those, that is a fixture worth keeping.
- [ ] `firmware/fwspi-u1.txt` has a version in it.
- [ ] With `CAPTURE_WRITES=1`: `api/write_rest_led_invalid.txt` contains an `errors` object with a
      class name in it.

A missing file discovered here costs a minute. Discovered next month it costs the fixture.

## Phase 3 — WebSocket transcripts, per unit

From the laptop. Each case is a separate fixture — the differences *are* the contract.

```sh
C=./tools/capture/capture-events.py

# default filter — the shape-inconsistency case
$C ws --host <ip> --unit l527 --label default --minutes 5

# canonical type filter — always an array, non-matching suppressed entirely
$C ws --host <ip> --unit l527 --label filtered --filter di,ro,do,ai,ao --minutes 5

# Home Assistant's actual filter: canonical and legacy names mixed in one list
# (research/07 req 6). One of the compat flags rests on what this does.
$C ws --host <ip> --unit l527 --label filtered-ha \
     --filter relay,led,input,ro,do,di --minutes 5

# {"cmd":"filter","devices":["default"]} — documented as a no-op in 3.0.6, and sent by
# Unipi's own v3 Node-RED node, so "no-op" needs to be observed rather than believed
$C ws --host <ip> --unit l527 --label filter-default --filter default --minutes 3

# cmd:all snapshot
$C ws --host <ip> --unit l527 --label all --cmd-all --minutes 1

# and once through nginx on :80 — the only path evok-ws-client has, since it offers no
# port option
$C ws --host <ip> --port 80 --unit l527 --label default-nginx --minutes 5
```

**During each run, make things change.** Toggle a DI. Warm a DS18B20 with your hand — that one is
the important one: 1-Wire events bypass the proxy and arrive as a **bare object** where Modbus
changes arrive as an **array**, and that single inconsistency is the most-reported client breakage
in EVOK's history. It is also where `dev: "temp"` appears instead of the canonical `sensor`. A
transcript without a 1-Wire event in it does not pin either down.

The script prints a running frame count and warns if it captured zero.

## Phase 4 — webhook capture and cold-start payloads

Phase 1 must already be done on this unit — the stock `config.yaml` has to be captured before you
change it.

```sh
# on the laptop
./tools/capture/capture-events.py webhook --port 9099 --unit l527 --label complex --minutes 10
```

On the unit:

```sh
cp -a /etc/evok/config.yaml /root/config.yaml.stock   # belt and braces; phase 1 has it too
# under apis.webhook:
#   enabled: true
#   address: http://<laptop-ip>:9099/hook
#   complex_events: true
#   device_mask: ["di", "sensor", "watchdog"]
systemctl restart evok
```

Note `device_mask`: the **shipped config's `["input","wd"]` matches nothing**, because the
comparison is against the canonical names `di` and `watchdog`. Capture that failure too if you
have time — one run with the shipped mask (expect zero deliveries), one with canonical names.

Both delivery modes, since they are different payloads:

- `complex_events: true` → `POST` with the JSON array body, same payload as the WebSocket.
- `complex_events: false` → bare `GET`, `Content-Type: application/json`, **no body**.

1-Wire events raise a `TypeError` inside EVOK's handler and are swallowed, so **webhooks never
fire for sensors**. Warm a DS18B20 during the run and record the silence — the absence is the
evidence.

**Cold start.** Each restart in this phase is a free chance at a payload we cannot otherwise get:
between startup and the first scan pass, Modbus devices emit `"value": null`. Immediately after a
restart:

```sh
systemctl restart evok; for i in 1 2 3; do
  curl -sS "http://127.0.0.1:8080/rest/all" > /tmp/coldstart-$i.json; sleep 0.3
done
```

Keep all three. `null` versus `0` is exactly the distinction our own data model has to preserve.

Restore when done:

```sh
cp -a /root/config.yaml.stock /etc/evok/config.yaml
systemctl restart evok
curl -sS http://127.0.0.1:8080/version    # confirm it came back up
```

## Phase 5 — `start_index` baseline, L527 only

Finding 1.1's `test` disposition needs a recording of stock EVOK getting this **wrong**. A
regression test that never fails against the old behaviour proves nothing.

Section 3 of the L527 has 14 RO, so it splits into two blocks of 7.

1. Find the right file. Definition file names are the **`model` key — the two-hex-digit internal
   board code** (`00`, `13`, …), not the product name. `/etc/evok/autogen.yaml` maps each section
   to its model; check whether two sections share one, because editing a shared file changes both.
   Back it up outside `/etc/evok`: `cp -a /etc/evok/hw_definitions/<NN>.yaml /root/`.
2. Split section 3's RO feature into two blocks of 7. The second block needs **both**
   `start_index: 7` **and its own advanced `val_coil`** — addressing is `coil = val_coil + i`, so
   without advancing `val_coil` both blocks target coils 0–6 and there is no collision to observe.
   This is the M403 shape from research/06 §5.
3. `systemctl restart evok`.
4. Capture `GET /rest/ro/all` and `GET /rest/all`. The expected defect: `start_index` is ignored
   for `RO`/`DO`/`LED`, so the second block's circuits collide with the first's.
5. Prove which coil each circuit actually drives, through the **RO→DI loopback**: set each RO in
   turn and record which DI changes. This is the recording that makes the regression test
   meaningful.
6. Restore the stock definition and restart. Confirm `/rest/ro/all` matches the phase 1 capture.

Low voltage only. 24 V DC.

## Phase 6 — hardware questions that only a live unit answers

From `research/05` §7.4. The register reads are safe while EVOK runs — though its own polling is
in the way, so prefer `/rest/register/<unit>_<addr>` and expect `ENoCacheRegister` outside the
declared bands. **The extension bus items need `systemctl stop evok unipitcp` first**: two
processes cannot own `/dev/ttyNS0`, and racing for it produces failures nobody can explain.

- [ ] **`RS485 Configuration` baud + parity encoding** — only `14 = 19200` is verified; the rest of
      the table is reconstructed. Read the current value on a section whose bus config you know,
      and work backwards.
- [ ] **Unit-0 aggregate read spanning sections** — L527 only, the 3-section unit. Confirms the
      `+100×(n−1)` optimisation is safe, and shows what happens when one section is unhealthy.
- [ ] **`Synchronised DO/RO` + `Lock` as the DirectSwitch write path** — no `ForceOutput` register
      exists in the corpus, and without this a DirectSwitch-claimed output cannot be written at all.
- [ ] **`(Internal) RS485 Full Mode Configuration` (reg 100) and the `RS485 TERMIOS` band
      (500–503)** — programmatic serial setup, per-section only, not reachable via unit 0.
- [ ] **Board firmware version against the maps' `v1.0` label** — the maps may simply not describe
      a FW 5.x board. Compare `fwspi` output with what the corpus claims for that model.
- [ ] **Register 1007 `Interrupt Mask`** — just read and record the value. ADR-level position is
      settled (research/05 §8.7: EVOK never touches it, we drop it, revisit only if a latency
      requirement justifies it). This is data collection, not a spike.
- [ ] **xS11 and xG18: bus address, baud, and observed `t3.5` timing** — needs the bus, so evok
      stopped. Both are on hand, so the RS-485 path and the 16 ms extension-read figure are
      verifiable now rather than after the xS51 arrives. **Do not run `fwserial` casually** — it
      demands exclusive port access and uninterrupted power, and violating either bricks the
      extension.

Record answers as dated notes in `research/05` §7.4 and `research/02` — corrections to research
are dated and marked, never silent edits.

## Phase 7 — afterwards

- [ ] Tarballs unpacked into `fixtures/captured/<unit>/`, then **never edited again**. That
      directory is CODEOWNERS-gated; a change there needs an explicit statement of what changed
      about reality.
- [ ] `docs/plan/STATUS.md` blocked table updated — rows removed, not annotated.
- [ ] Phase 6 answers written into the research files, with dates.
- [ ] `COMPATIBILITY.md` seeded from the error-shape, write-envelope and CORS captures.
- [ ] This runbook deleted. It is a one-session document; once the fixtures exist it is a lie with
      a delay.
- [ ] Only now consider replacing EVOK on a unit — and migrate before purging.

## What this trip does not cover

Wiring-dependent work waits for the rig: the AO→AI loops, the DO→DI PWM counter check, the
fault-injection slave on bus B. Those need the second M527 (approved, not yet ordered) and the
harness built. The one loopback that matters today is RO→DI on the L527, and phase 5 uses it.
