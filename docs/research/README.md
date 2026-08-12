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
| [`11-roadmap.md`](11-roadmap.md) | Sequencing **rationale** — why the phases are ordered as they are, and what agent-driven development demands. **Superseded as a working document by [`docs/plan/`](../plan/README.md)**, which is authoritative for what to do next. Its M-numbered phases predate the N0–N10 restructure. |
| [`12-modularisation.md`](12-modularisation.md) | **The 2026-08-12 re-steer**, in full: drivers / APIs / main, the addressing scheme, introspection as the source of compat's table, the config and message sketches, and every alternative rejected along the way. Accepted, and recorded as ADRs 0008–0012 — this file carries the reasoning the ADRs compress. |

## Related, outside this directory

| Path | Purpose |
|---|---|
| [`../GOALS.md`](../GOALS.md) | Goals, non-goals, invariants, definition of 1.0. Authoritative. |
| [`../plan/`](../plan/README.md) | The executable plan. `STATUS.md` first. |
| [`../rules/`](../rules/code.md) | How we work: code, testing, docs, git. |
| [`../adr/`](../adr/README.md) | Settled decisions, immutable once accepted. |
| `../modbus-reg-map/` | Official Unipi register maps. Ground truth, read-only. |
| `derived/model-io-census.csv` | Generated: DI/DO/RO/AI/AO/LED counts per model and section (83 rows). Use to validate hardware definitions at load time. |
| [`appendix/raw-hardware-research.md`](appendix/raw-hardware-research.md) | Full unedited hardware research report (register tables, model lists, KB citations). |
| [`appendix/raw-bug-archaeology.md`](appendix/raw-bug-archaeology.md) | Full unedited bug report (~90 findings with commit hashes and issue numbers). |

## Evidence conventions

Used consistently across these notes:

- **[V]** — verified against a URL, a commit, or a file we read.
- **[V-src]** — verified by reading EVOK 3.0.6 source.
- **[I]** — inference; flagged so it is never mistaken for fact.
- **[GAP]** — known unknown; the source is an image, a binary, or simply doesn't say.

Do not promote an `[I]` to a fact during implementation without re-verifying — several
of them (register offsets, baud-rate encodings) would produce silently wrong hardware
behaviour if wrong.
