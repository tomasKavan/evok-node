# evok-node research notes

Background research for **evok-node** — a Node.js / TypeScript drop-in replacement for
Unipi Technology's EVOK API.

Compiled 2026-07-27. Reference implementation studied: `UniPiTechnology/evok`
at commit `47c95c8` (branch `main`, latest tag **3.0.6**, 2025-09-02).

## Project premise

> **Superseded as the statement of goals, 2026-08-10.** Goals and non-goals are now stated in
> [`docs/GOALS.md`](../GOALS.md), which is authoritative — including the definition of 1.0, the
> post-1.0 direction, and the invariants that follow from them. What remains below is the
> *research premise*: the scope assumptions under which these notes were compiled. Where the two
> differ, `GOALS.md` wins.

- **Target**: EVOK **3.x** compatibility only. v2 is out of scope (upstream itself
  declares v2→v3 migration unsupported).
- **Compatible surface**: all APIs (REST, JSON, Bulk, WebSocket, Webhook, JSON-RPC),
  the `config.yaml` tree, `hw_definitions/*.yaml`, and the aliases file.
- **Device self-description**: same model as EVOK — device identity from the OS image
  (`unipiid` / `unipi-os-configurator` → `autogen.yaml`) plus per-model hardware
  definition files.
- **Primary goal**: stability and reliability. The Python implementation is a decade of
  accumulated fixes with a long tail of open, known defects; we inherit the *interface*,
  not the *design*.
- **Secondary goal (not v1)**: a lower-level local transport (unix socket / in-process
  API) so co-located low-latency consumers don't have to pay for HTTP/WS.

## Files

| File | Contents |
|---|---|
| [`00-sources.md`](00-sources.md) | Annotated source index: what we read, where it lives, what is machine-readable, what could not be obtained. |
| [`01-evok-api-surface.md`](01-evok-api-surface.md) | The compatibility contract. Routes, per-device-type payload shapes, WS/webhook/bulk/RPC semantics, error shapes, and **every doc↔code discrepancy found**. |
| [`02-hardware-model.md`](02-hardware-model.md) | Unipi product families, sections/coprocessors, identification registers, Modbus register-map conventions, per-family behavioural forks. |
| [`03-config-and-hw-definitions.md`](03-config-and-hw-definitions.md) | `config.yaml`, `autogen.yaml`, aliases file, `hw_definitions` schema — with the parsing rules and traps. |
| [`04-known-bugs-and-lessons.md`](04-known-bugs-and-lessons.md) | Condensed bug archaeology and the design rules it implies, ordered by severity. |
| [`05-evok-node-design-notes.md`](05-evok-node-design-notes.md) | Open design questions and decisions to make before implementation, incl. the low-level transport idea. |
| [`06-register-maps.md`](06-register-maps.md) | The official Modbus map corpus in `docs/modbus-reg-map/`: inventory, CSV schema, the gaps it closed, and a correction to `02`. |
| [`07-client-compatibility.md`](07-client-compatibility.md) | What must be byte-compatible for the Node-RED / Home Assistant baseline: 22 hard requirements from reading every known EVOK client, plus the surface nobody uses. |
| [`08-latency-and-scan-budget.md`](08-latency-and-scan-budget.md) | Why a full xS11 read takes 16 ms, what the levers are, and the scan-scheduling constraints that follow. |
| [`09-test-hardware-coverage.md`](09-test-hardware-coverage.md) | What the available Patron/Gate units exercise, the coverage gap on the highest-severity bug, and purchasing priorities. |
| [`10-test-kit.md`](10-test-kit.md) | The three-tier test kit: generated simulator, hardware-in-the-loop rig with software-controlled fault injection, soak and client acceptance. Designed to be driven by agents, not humans. |
| [`11-roadmap.md`](11-roadmap.md) | Sequencing **rationale** — why the phases are ordered as they are, and what agent-driven development demands. Its M-numbered phases predate the N0–N10 restructure in `15`, which is itself now superseded. Read for the arguments, not the order. |
| [`12-modularisation.md`](12-modularisation.md) | **The 2026-08-12 re-steer**, in full: drivers / APIs / main, the addressing scheme, introspection as the source of compat's table, the config and message sketches, and every alternative rejected along the way. Recorded at the time as ADRs 0001–0004; this file carries the reasoning those compress, and outlives them. |
| [`13-config-and-hw-definition-format.md`](13-config-and-hw-definition-format.md) | The proposed config and hardware-definition format, in detail. Was `plan/hw-definition-format.md`. |
| [`14-bug-dispositions.md`](14-bug-dispositions.md) | Every known EVOK finding and the disposition proposed for it. Was `plan/bug-dispositions.md`. |
| [`15-roadmap-to-rework.md`](15-roadmap-to-rework.md) | The N0–N10 roadmap as it stood on 2026-08-16. **Superseded, kept for its sequencing arguments** — the plan is being rebuilt from the development documentation, not from this. Was `plan/roadmap.md`. |

## Subdirectories

| Path | Contents |
|---|---|
| [`to_revision/`](to_revision/README.md) | **All 14 ADRs, as of 2026-08-16.** Reclassified as research pending revision; the immutability lock is lifted and nothing binding may cite them until they are re-locked. |
| [`modbus-reg-map-notes/`](modbus-reg-map-notes/README.md) | What is *ours* about a Unipi register map: how a source was read, what a transcription inferred, what to verify first. |
| [`derived/`](derived/) | Generated data: `model-io-census.csv`, DI/DO/RO/AI/AO/LED counts per model and section (83 rows). Use to validate hardware definitions at load time. |
| [`appendix/`](appendix/) | The two full unedited reports the condensed notes were written from. |

## Related, outside this directory

| Path | Purpose |
|---|---|
| [`../GOALS.md`](../GOALS.md) | Goals, non-goals, invariants. Authoritative — but the definition of 1.0 currently reads TBD. |
| [`../plan/`](../plan/README.md) | The plan: `STATUS.md` for current state, `roadmap.md` for the milestone sequence. |
| [`../rules/`](../rules/code.md) | How we work: code, packages, testing, docs, git. |
| [`../dev/`](../dev/README.md) | The design these findings feed into. Written from research, and allowed to overrule it about *what we build*. |
| [`../modbus-reg-map/`](../modbus-reg-map/README.md) | Official Unipi register maps. Ground truth, read-only, and no prose. |

The two appendix reports, cited throughout: full unedited
[hardware research](appendix/raw-hardware-research.md) (register tables, model lists, KB citations)
and [bug archaeology](appendix/raw-bug-archaeology.md) (~90 findings with commit hashes and issue
numbers).

## Evidence conventions

Used consistently across these notes:

- **[V]** — verified against a URL, a commit, or a file we read.
- **[V-src]** — verified by reading EVOK 3.0.6 source.
- **[I]** — inference; flagged so it is never mistaken for fact.
- **[GAP]** — known unknown; the source is an image, a binary, or simply doesn't say.

Do not promote an `[I]` to a fact during implementation without re-verifying — several
of them (register offsets, baud-rate encodings) would produce silently wrong hardware
behaviour if wrong.
