# ADR-0017 — nginx remains the `:80` front end for the compat surface only

- **Status:** Accepted — handling of evok's own nginx site pending the capture trip
- **Date:** 2026-08-12
- **Refs:** docs/research/07-client-compatibility.md §5, §2 (#1, #12) ·
  docs/research/05-evok-node-design-notes.md §8.9 · docs/research/12-modularisation.md §Settled ·
  docs/research/04-known-bugs-and-lessons.md finding 4.7 · ADR-0002, ADR-0008 · docs/GOALS.md G-2

## Context

Four clients hardcode or default to port 80, and HA's `evok-ws-client` hardcodes
`ws://<ip>/ws` with **no port option** — so without something on `:80` our stated HA baseline
cannot be configured at all. [research/07 §5](../research/07-client-compatibility.md) decided: keep
nginx, ship no `:80` listener, listen on `:8080` exactly as EVOK does.

That was written when there was one surface. ADR-0008 split it in two, and
[research/12](../research/12-modularisation.md) then settled that `api-nextgen` serves the built SPA
at `/` when `ui: true`. Both decisions have an opinion about who answers `/`, so they have to be
reconciled rather than filed side by side.

## Decision

**The `:80` requirement is scoped to the compat surface, and the two surfaces do not share a front
end.**

- **`api-compat`** listens on `:8080` with EVOK's paths. **nginx in front on `:80` remains a
  documented deployment requirement for it.** The stock `evok` nginx site works unchanged because our
  port and paths match; we ship a reference site file for from-scratch installs, and we neither
  generate nor edit one — finding 4.7 is ten "fix nginx autodetection" commits deep and is precisely
  that failure class.
- **`api-nextgen`** serves its own API and, when `ui: true`, the built SPA at its own `/`, same
  origin, from a packaging path rather than a bundled import — so nothing imports `ui`. **A
  nextgen-only install needs no nginx at all**, which is what the greenfield half of the drop-in
  guarantee requires.

**The older decision is narrowed, not overruled.** research/07 §5's "we do not ship a built-in `:80`
listener" holds, and its subject is now named: it governs `api-compat`. It never governed a surface
that did not exist when it was written, and reading it as "evok-node serves no root path anywhere"
would forbid the SPA that research/12 settled. Two listeners, two roots, no collision: nginx's site
maps only EVOK's prefixes, and the SPA is nextgen's own catch-all fallback.

## Consequences

Carried over from research/07 §5 unchanged, and load-bearing:
`proxy_read_timeout 180` on `/ws` means the compat WebSocket must produce traffic well inside it — a
server-initiated ping about every 20 s, which also satisfies `unipi-mqtt`'s 8 s pong requirement. And
**an integration test must run through nginx**, since the HA baseline only ever talks to the proxy, so
a proxy-only failure would be invisible in direct tests.

Makes easy: a greenfield box with no nginx, no CORS story and no endpoint configuration for the SPA;
and an unchanged nginx site for every existing EVOK deployment.

Makes hard: two ways in, so "which port am I on" has two answers and the install documentation has to
say so. Because the SPA is the catch-all, nextgen's reserved route prefixes cannot change later
without breaking SPA deep links — choose them once, at N6.

**Rejected: our own `:80` listener fronting both surfaces.** It collides with the stock evok site —
two nginx servers claiming `default_server` means nginx will not reload (ADR-0002) — needs root or
`CAP_NET_BIND_SERVICE`, and it puts the unauthenticated compat surface and the privileged
configuration surface behind one origin, which is the separation G-2 exists to keep.

**Rejected: serving the SPA through nginx.** It needs a generated or hand-edited site file on every
greenfield box (finding 4.7), and the SPA does control and configuration — its trust boundary should
be `api-nextgen`'s, not an nginx config we already know goes wrong.

**Rejected: putting `api-compat` on `:80` directly and dropping nginx.** Same privilege and
site-conflict problems, and it would diverge from EVOK's `:8080`, which is the one thing making the
existing site file work untouched.

**Still open, deliberately:** how the admin surface's authentication interacts with this front end
(GOALS §Open, G-2), and the exact `Conflicts:`/site handling for evok's own `:80` site file, which
needs the capture trip's `nginx -T` output (ADR-0002).
