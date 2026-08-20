# Roadmap — from research to code

> **Superseded as a working document.** The executable plan now lives in
> [`docs/plan/`](../plan/README.md) — `STATUS.md` for current state, `roadmap.md` for milestones,
> `milestones/M*.md` for tasks with acceptance criteria. **That is authoritative; this is not.**
>
> This file is retained as the **sequencing rationale**: why the phases are ordered the way they
> are, and what agent-driven development demands that a human team wouldn't. Read it once to
> understand the shape; work from `docs/plan/`.

Research is done. This is the ordered path to implementation, arranged around one constraint:
**the work will be done by coding agents.** That changes the sequencing more than it changes the
content — agents need a fast, deterministic, high-signal test loop before they can be productive,
and they need the project's rules written down rather than implied.

---

## Phase 0 — Repository and agent scaffolding

Do this first, because everything an agent does depends on it.

1. **`CLAUDE.md` at the repo root** — the operating rules, not a README. Should encode:

   > **Correction, 2026-08-12.** Implemented differently, and better. `CLAUDE.md` holds no rules of
   > its own: it carries the read order, the precedence chain and the citation scheme, and every rule
   > below lives in exactly one numbered home in `docs/rules/` — the non-negotiables as RC-8, RC-14,
   > RC-6, RC-4, RC-17, RC-18; the library rule as RC-22; the layering constraint as RC-10; test-first
   > as RT-3 and RT-8. The list that follows is the round-1 requirement, kept as evidence of what had
   > to be covered.

   - the non-negotiables from `04-known-bugs-and-lessons.md` (no bare catch; every wait has a
     deadline; transport results are discriminated unions; definitions are frozen; identity is
     never derived from a loop counter; duplicate circuit/coil registration is fatal);
   - the project rule *prefer a widely-used, tested, actively maintained library, behind a
     replaceable interface*;
   - the layering constraint: `core/` must never import from `api/`;
   - where the research docs live and that they are the source of truth for hardware behaviour;
   - test-first: no hardware-facing code without a generated table test.
2. **Package layout** enforcing the library-first decision (`05` §7.2): `core/` with no API
   dependency, API adapters as separate subpaths or packages, and a lint rule or dependency-cruiser
   config that fails the build on a violation. Agents will otherwise erode this boundary silently.
3. **TypeScript strictness maxed** — `strict`, `noUncheckedIndexedAccess`,
   `exactOptionalPropertyTypes`, `noImplicitOverride`. Most of the upstream bug tail is state
   problems the compiler can catch, but only with these on.
4. **ADRs** — convert the research decisions into numbered, dated Architecture Decision Records
   so an agent can read *why* and not relitigate. One per decision in `05` §7–§8: EVOK 3.x only,
   library-first, `modbus-serial`+wrapper, overlay definitions, nginx front end, Node 24, fastify,
   scope, compat flags.
5. **Fastify** as the HTTP layer (decided). Its JSON-Schema-first design maps directly onto
   EVOK's own `schemas.py`, so the POST validation transcribes almost 1:1.

## Phase 1 — Generated fixtures and the simulator

**The most important phase.** Without it agents have no inner loop and will start guessing.

6. **Map-corpus parser** → typed model descriptors from `docs/modbus-reg-map/`. Committed
   generated output, so a regeneration diff is reviewable.
7. **Generated address tables** for every model and section in the corpus, including the
   discontinued 28-RO / 30-DI Neurons. Per `10-test-kit.md` §4 this is now the *primary*
   safeguard for the highest-severity bug class, not a supplement.
8. **Modbus slave simulator** with real register layout, bit packing, unit-0 offsets, and
   protocol-level fault injection.
9. **Codec layer + golden tables** — CDAB word swapping, `float32`, raw 0..4000 AO counts,
   resistance scaling, negatives, boundaries, NaN→`null`.
10. **Golden-transcript replay harness**, ready to consume the captures from Phase 2.

## Phase 2 — Capture from real hardware *(human, time-sensitive, parallel)*

Do this while the Patrons still run stock EVOK. Once replaced, it's unrecoverable.

11. **Golden API transcripts** from L527, M527, S167: `GET /rest/all`, per-type GETs, WS sessions
    (default filter and filtered), a webhook capture, `GET /json/all`. L527 first — three sections,
    both AI abstractions, the 16-DI boundary.
12. **Stock artefacts**: `/etc/evok/hw_definitions/*.yaml`, `/etc/evok/autogen.yaml`,
    `unipiid` output (or sysfs equivalent on Debian 12), per-section firmware versions, and the
    nginx site file.
13. **Baseline measurements** to compare against later: idle CPU, per-block scan timing, the
    16 ms extension read, and the p99 API latency of stock EVOK.

## Phase 3 — CI/CD

14. Lint, typecheck, unit tests, generated-fixture drift check (regenerate and fail on diff),
    simulator integration tests, coverage gates on the hardware-facing modules specifically.
15. **Self-hosted runner on the test host** with a `hardware` job label, so HIL tests run on
    merge to main rather than on every commit. Tier 0 must stay fast enough for every push.
16. Release automation: conventional commits, changesets, npm publish, and only later a Debian
    package.

## Phase 4 — The rig: wiring *(human)* and the rig service *(agents)*

17. **Wiring and enclosure** *(human, parallel with 0–3)* — per `10-test-kit.md`: cross-unit
    loopbacks, the test-host Patron's RO/DO as power and bus switching, 1-Wire sensors with one
    on a switchable line, RS-485 bus A to extensions and bus B to the test host.
18. **Test-host preparation** *(human)*: `systemctl disable --now evok unipitcp` on the rig
    controller so it doesn't hold the RS-485 ttys or poll its own boards; keep
    `unipi-kernel-modules` for sysfs.
19. **`packages/rig` — a codeable deliverable.** A small TypeScript service deployed on the
    test-host M527, exposing the `rig` CLI/HTTP surface. **Hard constraints, enforced by a
    dependency rule in CI:**
    - **must not import anything from evok-node `core/`** — the instrument cannot share code with
      the thing it measures, or a shared bug makes a test pass that should fail;
    - **must not use a Modbus client at all** — I/O goes through **sysfs** file reads/writes
      (`/run/unipi-plc/by-sys/…`), a completely different mechanism from the code under test;
    - minimal dependencies, deliberately boring, no clever abstractions;
    - `rig reset` must always return the rig to a known-good state, including after a crashed run.
20. **Fault-injection Modbus slave** — a separate small binary on the test host bound to
    `ttyNS1`, driving bus B. This one *does* need serial framing, but as a **server**, so it still
    shares no code with the client under test. It must be able to violate the protocol on demand
    (late responses, bad CRC, wrong unit id, silence, t3.5 violations) — that is its entire
    purpose, so it cannot be built on a library that prevents malformed output.
21. **`rig loopback verify`** — proves the rig itself is sound, end to end, *before* any
    evok-node code depends on it. Run it as a CI precondition for the `hardware` job: if the rig
    is miswired, hardware tests must fail loudly rather than mysteriously.

### CI topology consequence

The **rig controller and the CI runner are different machines** (`10-test-kit.md`: 1 GB RAM /
8 GB eMMC is fine for a long-running service, poor for build churn, and CI writes wear
non-replaceable eMMC). So the `hardware` job runs on a separate runner and *drives* the rig over
the network. Tier 0 needs no rig at all and runs on generic runners.

## Phase 5 — Implementation, transport-first

Order by risk, not by architecture-diagram tidiness. The transport is where the silent-wrong-data
failures live, so it goes first and gets verified hardest.

20. **Modbus transport wrapper** — the eight non-negotiables in `05` §8.4: per-port mutex, RX
    flush before every request, strict unit/FC gate with CRC-before-consume, t3.5 pacing, outer
    deadlines, reconnect supervisor, retry-with-backoff on idempotent reads only, TCP request cap.
    Verified against the fault-injection slave, including the stale-frame-desync case that every
    mature library gets wrong.
21. **Definition loader** — base → overlay → site merge, strict schema, frozen output, provenance
    per field, and the load-time validations from `03` (multi-word values within one block;
    computed addresses inside a declared block; global uniqueness fatal; census cross-check
    against registers 1001/1002).

    > **Corrected 2026-08-13 (ADR-0014).** There is **no merge and no per-field provenance**: our
    > definitions and the operator's `custom/` ones are disjoint namespaces, and an id resolves in exactly
    > one root. What the loader does instead: resolve an id to a file or to a `minFirmware` variant
    > directory, and run the handshake identity check (`hardwareId`, holding 1004) alongside the census.
    > Strict schema, frozen output and every validation listed above stand unchanged.
22. **Device model and registry** — discriminated unions, total decode functions, lifecycle state
    machine, staleness in the data model, monotonic counter totals.
23. **Scan scheduler** — per-bus, fixed-rate with drift correction and an explicit overrun policy,
    circuit breaker with hysteresis, bus time budget, MWD-aware.
24. **Identity providers** — `unipiid` → sysfs → register-based fallback chain (Debian 12 and 13).
25. **API adapters** — REST/JSON first (widest client use), then WebSocket, then webhook, bulk and
    JSON-RPC. Each validated against the golden transcripts and the 22 requirements in `07`.
26. **`doctor` / `/diagnostics` / `/metrics`.**
27. **Node-RED and Home Assistant acceptance through nginx** — the real gate on "compatible".

## Phase 6 — Hardening

28. Soak testing with injected faults; RSS and latency assertions.
29. Hardware verification checklist from `05` §7.4 — the RS485 baud encoding, whether Sync+Lock is
    the DirectSwitch write path, unit-0 aggregate reads.
30. Debian 12 and 13 install testing; packaging.

---

## What agents need that a human team wouldn't

- **A fast loop.** If the test suite takes minutes, agents lose the plot. Tier 0 must be seconds.
- **Deterministic failures.** No flaky hardware tests in the default loop; HIL is a separate,
  labelled job.
- **Generated over hand-written.** Anything derivable from the map corpus should be generated, so
  an agent cannot "fix" a failing test by editing the expected value. Consider making generated
  files read-only in CI.
- **Explicit invariants as executable assertions.** "Duplicate circuit id is fatal" as a runtime
  check *and* a test, not as prose in a doc an agent may not read.
- **Small, reviewable slices** with a single acceptance criterion each.
- **A written record of why.** ADRs exist so agents don't relitigate settled decisions from
  first principles.

## Suggested first three tasks

1. Phase 0 items 1–3 (scaffolding, layering, strict TS) — one session.
2. Phase 1 items 6–7 (map parser + generated address tables) — highest leverage single task in the
   project; it is the permanent substitute for hardware we can no longer buy.
3. Phase 2 item 11 (golden transcripts) — **human task, do it this week**, before anything touches
   the Patrons.
