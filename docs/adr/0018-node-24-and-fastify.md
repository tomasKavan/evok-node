# ADR-0018 — Node.js 24, and fastify for HTTP

- **Status:** Accepted
- **Date:** 2026-08-12
- **Refs:** docs/research/05-evok-node-design-notes.md §8.6, §8.11, §2.2 · RC-12, RC-22 ·
  ADR-0002, ADR-0005

## Context

Two dependency choices with long half-lives and no cheap reversal: the runtime floor, which packaging
and every API depend on, and the HTTP framework, which the shape of our route and validation code
depends on. Both were settled in
[research/05 §8.6 and §8.11](../research/05-evok-node-design-notes.md) and neither has an ADR.

## Decision

**Node 24.** Active LTS as of July 2026, EOL 2028-04-30. Keep the code 26-clean and use nothing that
would block a 26 bump; 22 is already in maintenance.

**fastify** in every package that serves HTTP. Its JSON-Schema-first design maps almost 1:1 onto
EVOK's own `schemas.py` — upstream's POST validation *is* JSON Schema — so the compat validation
transcribes rather than being re-derived, and schema-driven serialisation suits a fan-out path. Our
parse boundary is zod (RC-12) with `z.toJSONSchema()` feeding fastify's routes, so each schema is
written once, in the API package that owns that surface.

## Consequences

Makes easy: `node:sqlite` without a flag, which is what makes ADR-0005's store a dependency-free
choice; and transcribing compat's request validation from upstream instead of inventing it.

Makes hard: **neither Debian generation we support ships Node 24**, so packaging must declare a
runtime source or bundle one. That is an ADR-0002 item this decision sharpens, and it is on the same
capture-trip list — we need to know what evok's own packaging depends on before writing our
`Depends:`. `node:sqlite` is also still a release candidate on the minor we pin (STATUS open question
4, ADR-0005); the fallback is `better-sqlite3`, which needs armhf/arm64 prebuilds.

**Rejected: `node:http` plus a small router**, which research/05 §2.2 held open on install-footprint
grounds for a 1 GB Neuron. The footprint argument did not survive contact with the work it saves:
hand-rolled routing and validation is exactly where a compat shape bug would live, and fastify's tree
is small next to `serialport` and the definition corpus.

**Rejected: express.** No schema-first story, so validation and serialisation are hand-written, and
its serialisation is slower on the one path where we fan out to N WebSocket clients.

**Rejected: Node 22** (maintenance — the floor would need raising inside 1.0's life) and **Node 26**
(not LTS until October 2026, so it would ship a non-LTS runtime to industrial controllers).

**Rejected: supporting a range of Node majors.** One runtime is one test matrix. The packaging pins
it, and an embedder consuming the libraries (ADR-0014) is free to be ahead of us but not behind.
