# ADR-0006 — Administration never rides on the classic surface

- **Status:** Accepted — mechanism deliberately deferred
- **Date:** 2026-08-10
- **Refs:** docs/GOALS.md invariant 2, invariant 3 · docs/research/04-known-bugs-and-lessons.md rule 29, finding 4.6 · docs/research/07-client-compatibility.md §5 (nginx front end)

## Context

EVOK's API is unauthenticated. `check_origin` returns `true` unconditionally and issue #149 on
authentication is still open (research/04 rule 29). Deployments rely on the network being trusted —
nginx on `:80`, LAN only. We inherit that surface unchanged, because changing it would break every
existing client, and the compat surface is permanent and first-class (invariant 3).

The post-1.0 direction adds administration and introspection: PLC configuration, network
configuration, processes and resource consumption, log access, and a rule engine that drives
actuators. Exposing any of that at the compat surface's trust level would make an unauthenticated
LAN service into a privileged control and configuration plane.

## Decision

**Administration and introspection are never reachable through the classic (compat) API.** The
compat surface keeps exactly the trust model it has today and gains nothing.

Whether an instance exposes the classic surface, the new API with administration, or both, is a
**configuration choice** — stated here so that no future change quietly adds a privileged route to
`/rest`.

The **mechanism is deferred**: separate ports versus separate paths, the authentication scheme, and
whether the admin surface is off by default are settled when the admin surface is designed, in a
superseding ADR. Deciding them now, with no implementation to test against, would produce a
decision nobody has validated.

## Consequences

Makes easy: keeping the compat promise absolutely — no client sees any change. Reasoning about blast
radius, because the privileged surface is a separate thing that can be disabled entirely.

Makes hard: any feature wanting to serve both audiences must be implemented against both surfaces, or
be admin-only. Some diagnostics are genuinely useful to plain clients; research/04 rule 35's
`/diagnostics` is in 1.0 and must therefore be scoped to non-sensitive, read-only content, with
anything touching processes or network configuration held back for the admin surface.

**Now owed, before the admin surface is built:** the authentication scheme, the default-on/default-off
posture, and how this interacts with the nginx front end (research/07 §5). All three are listed in
`GOALS.md` §Open.

**Rejected:** authenticating the compat surface. It would break every existing client and defeat the
project's reason to exist. **Also rejected:** deciding the mechanism now — see above.
