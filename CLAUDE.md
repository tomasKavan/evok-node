# evok-node — agent operating rules

A Node.js/TypeScript drop-in replacement for Unipi Technology's **EVOK 3.x** API. EVOK is a
load-bearing part of Unipi's FOSS stack with a long tail of open, known defects; we exist to fix
them. The interface is inherited; the design is not.

Success is defined, not asserted: every finding in `docs/plan/bug-dispositions.md` has a
disposition, and the invariants below hold. See [`docs/GOALS.md`](docs/GOALS.md).

## Before you write code

1. **`docs/plan/STATUS.md`** — what is done, what is in progress, what is next. Always read first.
2. **`docs/GOALS.md`** — goals, non-goals, invariants, what 1.0 is. Read before arguing that
   anything is in or out of scope. Wins over every other document.
3. **`docs/rules/`** — [code](docs/rules/code.md) · [testing](docs/rules/testing.md) ·
   [docs](docs/rules/docs.md) · [git](docs/rules/git.md). Binding.
4. **`docs/adr/`** — settled decisions. Do not relitigate; propose a superseding ADR instead.
5. **`docs/research/`** — the knowledge base: how EVOK and Unipi hardware actually behave.
   Authoritative for hardware facts. Read the relevant file before touching that area.

If a rule and this file disagree, the rule file wins. If research and reality disagree, reality
wins — and you update the research file in the same PR, with a dated correction note.

## Inviolable rules

Violating any of these is a blocking review comment, and most are enforced in CI.

1. **`core/` never imports from `api/`, `server/` or `inspector/`.** Checked by
   `dependency-cruiser`. Further, **the core↔API contract is serialisable messages** — no
   callbacks, class instances or Buffers cross it. One process today; the process split must stay a
   deployment change, not a rewrite. See ADR-0013.
2. **`packages/rig` never imports any other workspace package** and never uses a Modbus client.
   The instrument must not share code with what it measures.
3. **No `any`, no `as` casts, no non-null `!`** outside generated code. Parse at the boundary,
   then the type is real.
4. **Expected failures are values, not exceptions.** Return a discriminated union
   (`{ok:true,…} | {ok:false, kind:…}`). `throw` is for programmer error only.
5. **A Modbus exception PDU is a failure.** Never a value a caller can mistake for success.
6. **Every wait has a deadline.** No unbounded loops, no promise without a timeout, no
   `setTimeout` without a paired abort path.
7. **No bare `catch {}` on any event or delivery path.** Log-and-count with dedup.
8. **Never derive an identity from a loop counter.** Addresses come from the single audited
   address function, which has the `/16` bank stride and `%16` mask in exactly one place.
9. **Duplicate circuit ids, or two circuits resolving to the same coil or (register, bit), is a
   fatal startup error.** This is what stops us silently driving the wrong relay.
10. **Hardware definitions are frozen and `readonly`** once loaded.
11. **Multi-register values must lie wholly inside one register block with one frequency.**
    Validated at definition load; violating definitions are rejected.
12. **Every reading carries `value`, `readAt`, `stale`.** No silent zeros, no frozen values
    without a staleness marker.
13. **One event envelope from every source**, `changes` always an array — including 1-Wire.
    Real clients crash otherwise.
14. **Never edit `fixtures/generated/` or `fixtures/captured/`.** If a test fails against them,
    the code is wrong. See [testing rules](docs/rules/testing.md).
15. **Prefer a widely used, tested, actively maintained library** over writing your own — behind
    an interface thin enough to replace it.
16. **The daemon never writes its own config file.** `/etc/evok-node/config.yaml` is operator
    intent, hand-edited. Runtime user data goes to the store in `/var/lib/evok-node/`; readings are
    never persisted. Three kinds of data, three lifecycles — see [`docs/GOALS.md`](docs/GOALS.md)
    invariant 5.
17. **Nothing new leaks into a compat payload.** The classic surface emits the flat projection of
    our model and nothing else — no new fields, no changed shapes, ever. Internal richness is
    invisible there.
18. **The daemon refuses to start if evok or `unipitcp` holds the buses.** Loudly, with the
    conflicting unit named. Two processes cannot own `/dev/ttyNS0`; racing for it produces
    unexplainable failures.

## Workflow

Issue → branch `<type>/<issue>-<slug>` → PR → green CI → Tomas approves → squash merge.
Conventional Commits. Update `docs/plan/STATUS.md` in the same PR as the work.

Tomas does not write code and reviews every PR. Optimise for **reviewability**: small PRs, one
concern, and a PR body that says what changed and how it was verified.

## Layout

```
packages/
  protocol/     wire schemas (zod) — the single source of truth for the API contract
  modbus/       transport: framing, correlation, timing, circuit breakers
  hw-definitions/  model descriptors, overlay definitions, generated address tables
  core/         registry, device model, scheduler, aliases. No API dependency.
  server/       fastify adapters: REST, JSON, bulk, WS, webhook, JSON-RPC. The daemon.
  client/       first-party TS client. Depends only on protocol.
  simulator/    Modbus slave simulator, generated from the map corpus
  inspector/    web UI. Public API only — never imports core.
  rig/          hardware-rig control service. Private, sysfs only, no workspace deps.
docs/
  plan/         what we are doing next
  rules/        how we work
  adr/          why we decided
  research/     what is true about EVOK and Unipi hardware
  modbus-reg-map/  official Unipi register maps — ground truth, read-only
```
