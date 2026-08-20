# Status

**Updated:** 2026-08-18 · **Milestone:** [M3 — development documentation](roadmap.md) ·
**Version:** unreleased

Present state only. What changed and when is what git is for; milestone sequence is in
[`roadmap.md`](roadmap.md).

**No implementation code exists.** Every package entrypoint is a placeholder export.

## Done

**M1 — Research.** [`docs/research/`](../research/README.md) is the knowledge base: EVOK 3.x API
surface, Unipi hardware model, config and hw-definition formats, upstream bug archaeology (29
condensed findings from ~90 raw), client compatibility matrix, latency budget, test-kit design, and
the register-map corpus imported and indexed under
[`docs/modbus-reg-map/`](../modbus-reg-map/README.md). [`GOALS.md`](../GOALS.md) is authoritative on
scope: the goal, its measurable form, the invariants, the drop-in guarantee, the non-goals. *What 1.0
is* reads **TBD** — M3 settles it.

**M2 — Repo scaffolding.** npm workspaces over thirteen packages; a shared strict TS base; vitest in
workspace mode with coverage floors wired and switched off; `pr` and `main` CI workflows with actions
pinned by SHA; eslint with the type-checked config; `dependency-cruiser` carrying the layering DAG.
`npm run build`, `test`, `lint` and `layering` each exit 0 — 27 modules, 13 edges, no violations.

## In progress

**M3 — development documentation.** [`docs/dev/`](../dev/README.md), files `00`–`21`.
[`00-Intro.md`](../dev/00-Intro.md) **is written; `01`–`21` are still memos with no content.** Written
from the research above, settled by discussion as it goes. It also has to produce three things beyond
itself: the architecture it commits to, an answer to every proposal in
[`research/to_revision/`](../research/to_revision/README.md), and *What 1.0 is*.

Settled in the `00` pass, and affecting how everything after it is written:

- **The ADR set is dissolved rather than re-locked** (`dev/00 §Where decisions live`). `docs/dev/` is
  the only home for a decision and the reasoning behind it. The fourteen files under
  `research/to_revision/` are proposals binding on nothing, each owed an answer by a named dev file —
  the **Absorbed by** column of that index is the only mechanical completeness check M3 has, and it
  currently reads `owed` on eleven of fourteen rows.
- **`docs/dev/` is authoritative over the code.** RD-8 was inverted on 2026-08-18: code contradicting a
  dev doc is a defect in the code, and changing a design is a human decision stated under its own
  heading in the PR body (RG-6).
- **Two proposals were rehomed** because no dev file owned them: hardware scope to
  `GOALS §Hardware scope`, instrument independence to RT-15.

Carried over from M2, independent of M3, and landable at any time:

- **Licence undecided** — MIT or Apache-2.0.
- **Repo hygiene and `npm run verify`** not done.
- **Four of the `pr` workflow's eight checks are placeholders** — `format` and `changeset` until repo
  hygiene lands, `fixture-drift` until there are fixtures, `coverage` runs but enforces nothing until
  there is something to cover. Each prints a warning annotation.
- **Branch protection is not configured** — Tomas's to set. The workflows run; nothing requires them
  to be green.

## Next

**Not yet defined.** M3 defines it (RPL-4). No milestone numbers past M3 exist, and none should be
invented.

## Blocked / waiting on hardware

Independent of M3 — hardware does not care about our documents. All three Patrons are **confirmed
still stock**, and the golden transcripts are **unrecoverable once EVOK leaves them**, so the capture
work is time-sensitive wherever it lands in the plan. **Do not `apt purge evok` on any Patron before
migrating** — purge destroys the fixtures below. There is no capture runbook; one gets written when
the plan calls for it, from this list.

| Item | Waiting on |
|---|---|
| Golden transcript capture | **Human task, time-sensitive.** Stock EVOK 3.0.6 on L527/M527/S167 — **and the Gate, if it still runs stock EVOK**, since research/09 §1 makes the zero-local-I/O payload a named requirement. |
| **Gate behaviour with no onboard driver** | Same trip, load-bearing: `api-compat` allows **at most one** onboard driver, and zero is the Gate, which must serve an empty API rather than erroring. research/09 records EVOK's own `readboards()` and `/rest/all` degrading oddly here, so the shape must be captured, not inferred. |
| Stock `hw_definitions` + `autogen.yaml` + firmware versions | Same trip. **Blocking:** the shipped `hw_definitions` are the only source of AI/AO **mode enumerations** for CSV-only families, and G-3 makes those mandatory — board `00` cannot be written without them. Edge and Unipi 1.1 are unaffected; their XLSX `Description` sheets carry the enums. |
| Register 1004 (Hardware ID) per unit | Same trip. Seeds `identifies.hardwareId`; a model without it falls back to the census check, which is normal rather than incomplete. |
| Which `run.d` directory exists, and what owns it | Same trip, cheap: `ls -ld /usr/lib/unipi/run.d /opt/unipi/os-configurator/run.d` plus `dpkg -S`. Upstream documents the first, Debian 12 shows the second. Our `postinst` installs into whichever exists. |
| Stock `config.yaml` + `/var/lib/evok/alias.yaml` | Same trip. The migration tool's golden fixtures. |
| evok packaging — systemd unit names and its nginx site file | Same trip. Known already: `evok` declares `Depends: python3` only; `apt-get -s remove --auto-remove evok` takes `evok`, `evok-web`, `nginx`, `nginx-common`, and `evok-unipi-data` survives — so we need `Depends: nginx`, not `unipi-kernel-modules`, and no Unipi data package. Outstanding: the unit names and the `:80` site conflict. |
| `start_index` old-behaviour baseline | **Same trip, easy to forget.** Finding 1.1's `test` disposition needs a transcript of stock EVOK mis-registering a deliberately split RO definition (two blocks of 7 with `start_index`) on the L527's section 3. |
| Second Patron M527 as rig test host | **Approved, not yet ordered.** Blocks all tier-1 hardware tests. **Image it Debian 12** — all three existing Patrons run Debian 13, so the Debian 12 identity path otherwise has no test host, and it arrives blank so this costs no fixtures. |
| xS51 extension | **Approved, not yet ordered.** AI/AO over RTU (float32 AI, raw-count AO, 6-mode enum on an extension) is otherwise only reachable via the local TCP path. |
| Tier-1 hardware tests | Rig not built. Needs the M527 above, wiring, and the `rig` service. Parallel track; gates nothing (RPL-7). |
| RS485 baud-encoding, DirectSwitch write path, unit-0 aggregate reads, register 1007 semantics | Verification on hardware; see [research/05](../research/05-evok-node-design-notes.md) §7.4. Partly answerable on the capture trip. |
| Neuron and Unipi 1.1 support | Hardware not purchased. Map-driven and simulator-verified until then. Buy an **L203** when a Neuron is bought. |

On hand and usable today: **xS11 and xG18** extensions — the xG18 makes 1-Wire over RTU coverable
now.

## Known permanent gaps

**No purchasable Unipi device has >16 channels of one type in a single section**, so the
*missing-bank-stride* half of the highest-severity bug class — silently driving the wrong relay — can
never be verified on hardware. Mitigated by generated address tables plus the fatal-on-duplicate-
registration assertion (RPG-DRV-3). The `start_index` half **is** reproducible, on the L527's section
3 via a deliberately split definition and the RO→DI loopback. See
[research/10 §4](../research/10-test-kit.md) and
[research/14](../research/14-bug-dispositions.md) finding 1.1.

## Open questions

1. **`node:sqlite` stability** on the Node 24 minor we pin — available without a flag, but a release
   candidate rather than fully stable. Fallback is `better-sqlite3`, which needs armhf/arm64
   prebuilds. `driver-store`'s problem, not the daemon's.
2. **Two workspace dependency edges are deliberately undeclared**, because declaring one wrongly is
   what `dependency-cruiser` then enforces:
   - `client → api-nextgen`. The client targets that surface's public schema, which does not exist
     yet. The alternative is a separate `schema-nextgen` package, so the client need not depend on a
     server package at all. Decide when the schema lands.
   - `ui → client`. Decide before `ui` starts.
3. **`typescript` is pinned to `~6.0.3`, not the current `latest` (7.0.2).**
   `typescript-eslint@8.66.0` declares `typescript >=4.8.4 <6.1.0`, so the type-checked lint config — our load-bearing layering and
   no-`any` guard — cannot run on TS 7. The `~` is deliberate: `^6.0.3` would allow 6.1 and break
   lint. Revisit when `typescript-eslint` supports the native compiler.
4. **`data_point` is overloaded and must not be allowed to converge.** It is a specific EVOK type
   (id 24, `<device_name>_<register_address>`, `datatype: null|float32`); our generic term for
   anything addressable is **endpoint**.
5. Deferred by design, listed so they are not mistaken for oversights: trigger-engine fail-safe
   semantics, the admin-surface authentication mechanism, and the plugin isolation model — the last
   narrowed by G-1's one-process-for-now, which leaves the message boundary as the thing that keeps the
   options open. **This list is their only record** — `GOALS.md` has no Open section, so do not delete
   these lines without moving them somewhere permanent.
