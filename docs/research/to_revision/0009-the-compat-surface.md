# ADR-0009 — The compat surface: stock EVOK 3.0.6, five flags, port 8080, no administration

- **Status:** Accepted — the privileged surface's own authentication deferred; handling of evok's
  nginx site pending the capture trip
- **Date:** 2026-08-12
- **Refs:** docs/research/01-evok-api-surface.md §9 · docs/research/07-client-compatibility.md §2,
  §4, §5, §6, §7 · docs/research/05-evok-node-design-notes.md §2.1, §7, §8.9 ·
  docs/research/04-known-bugs-and-lessons.md R04-29, findings 4.6, 4.7 ·
  docs/GOALS.md G-2, G-3, §Non-goals · RC-21, RD-3 · ADR-0001, ADR-0003, ADR-0006

## Context

"Compatible with EVOK" is not one target. EVOK has two incompatible generations and its v2 device names
are still being written into new clients — `unipi-mqtt-ng` was published in **February 2026** against
v2 names and is therefore completely broken on EVOK 3 — while upstream declares v2→v3 migration
unsupported. Even within v3, EVOK's documentation and code disagree in twelve places
([research/01 §9](../01-evok-api-surface.md)), so there are two candidate contracts.

Two further facts shape the surface rather than the contract. EVOK's API is **unauthenticated** —
`check_origin` returns `true` unconditionally and issue #149 is still open (R04-29). And four clients
hardcode or default to port 80: HA's `evok-ws-client` hardcodes `ws://<ip>/ws` with **no port option**,
so without something on `:80` our stated HA baseline cannot be configured at all.

## Decision

**The oracle is stock EVOK 3.0.6 as deployed on Unipi OS**, cross-read against upstream `main` at
`47c95c8`. Nothing earlier is a target. Where documentation and code disagree, **the code is the
contract** — clients were written against the running server. Where the code is outright broken (bulk
`group_*`, static 1-Wire sensors, RPC method signatures, `register` events, alt-name filters) we
implement the documented intent correctly and **with no flag**: no working client can depend on a
`TypeError`. **Alt-name acceptance on input is permanent** — that is EVOK 3 behaviour, not a v2
concession, and February 2026's client is the argument for keeping it forever.

**The flag set is exactly five, and closed.** A new payload fix does not mint a new flag without an ADR
(G-3). Every default reads backwards at first glance, so each has a named client behind it:

```yaml
compat:
  wsAlwaysArray: true       # repairs HA and phillipsnick's node, which crash against EVOK today.
                            #   Not legacy: the flag exists only to reproduce EVOK's object/array
                            #   inconsistency for A/B testing against a transcript. RC-21 is the rule
  legacyErrorStatus: true   # live requirement, both halves, by different clients: unipi-mqtt checks
                            #   status_code == 200 and ignores success; the vendor web UI relies on
                            #   jQuery's error: callback; pimatic reads success and not the status
  batchEvents: false        # evok2mqtt does json.loads(payload)[0], so a batched frame silently drops
                            #   N−1 devices. EVOK batches, so matching it would be defensible; off is
                            #   strictly better for that client and costs only frame overhead
  acceptAliasPrefix: true   # repairs Unipi's own v3 Node-RED node, which still builds v2 al_<alias>
                            #   into circuit, so aliased set commands from it silently do nothing
  emitLegacyDevNames: false # opt-in only, per-connection at most: enabling it also needs relay_type
                            #   and dev:"neuron", which breaks every conforming client
```

**`api-compat` listens on `:8080` with EVOK's paths, and nginx in front on `:80` remains a documented
deployment requirement for it.** The stock `evok` nginx site works unchanged because our port and paths
match; we ship a reference site file for from-scratch installs, and we neither generate nor edit one —
finding 4.7 is ten "fix nginx autodetection" commits deep and is precisely that failure class.
`api-nextgen` serves its own API and, when `ui: true`, the built SPA at its own `/`, same origin, from a
packaging path rather than a bundled import, so nothing imports `ui`. **A nextgen-only install needs no
nginx at all,** which the greenfield half of the drop-in guarantee requires. research/07 §5's "we do not
ship a built-in `:80` listener" is narrowed, not overruled: its subject is `api-compat`.

**Administration and introspection are never reachable through this surface.** It keeps exactly the
trust model it has today and gains nothing. The mechanism is structural rather than configuration:
system introspection arrives as `driver-system`, an ordinary driver, and `api-compat` can only emit what
its projection table describes (ADR-0003) — that table has no entry for a `system` driver, so admin
cannot reach compat **even if an administrator lists it** in compat's `drivers:`.

## Consequences

Makes easy: a single oracle, so every compat claim is checkable against golden transcripts from one
stock 3.0.6 unit — what makes `COMPATIBILITY.md` a deliverable rather than a narrative (RD-3), one line
per divergence. Two of the five flags let us A/B our fixed behaviour against stock EVOK, which is how a
divergence gets attributed rather than argued about. A greenfield box needs no nginx, no CORS story and
no endpoint configuration for the SPA, while every existing EVOK deployment keeps its site file
unchanged. And blast radius is easy to reason about, because the privileged surface is separate and can
be disabled entirely.

Makes hard: **the oracle is perishable** — a behaviour nobody captured before EVOK leaves those Patrons
cannot be recovered, which is why the capture trip is time-sensitive rather than merely scheduled. Every
flag is a second code path with its own transcript test, which is why the set is closed. Two ways in, so
"which port am I on" has two answers the install documentation must give; and because the SPA is
nextgen's catch-all, nextgen's reserved route prefixes must be chosen once, at N6, or SPA deep links
break later. Any feature wanting to serve both audiences is implemented twice or is admin-only —
R04-35's `/diagnostics` is in 1.0 and must therefore be scoped to non-sensitive read-only content.

Carried over from research/07 §5 unchanged and load-bearing: `proxy_read_timeout 180` on `/ws` means the
compat WebSocket must produce traffic well inside it — a server-initiated ping about every 20 s, which
also satisfies `unipi-mqtt`'s 8 s pong requirement. And **an integration test must run through nginx**,
since the HA baseline only ever talks to the proxy.

**Now owed, before the admin surface is built:** its authentication scheme, its default-on/default-off
posture, and how both interact with the nginx front end. All three are in `GOALS.md` §Open. The exact
`Conflicts:`/site handling for evok's own `:80` file needs the capture trip's `nginx -T` (ADR-0006).

**Rejected:**

- **Bug-for-bug fidelity** — already a non-goal; recorded here because it is what a reader reaches for
  when a golden transcript and a fixed payload disagree. The answer is the closed flag set.
- **Emitting both vocabularies** so the three v2 clients work. research/07 requirements 6, 7 and 20 are
  precise about which spelling goes in which direction; emitting `relay` *and* `ro` breaks every client
  conforming to EVOK 3 to repair three that conform to nothing current.
- **Tracking upstream `main` rather than a release** — a moving target cannot be captured. We re-pin
  deliberately if 3.0.7 ships, as a dated note here and a re-capture.
- **No flags at all.** Four of the five defaults are simply "correct", but the fixed side of
  `wsAlwaysArray` and `legacyErrorStatus` cannot be A/B'd against stock EVOK without a switch, and
  `batchEvents` is a genuine choice.
- **`emitGlobDevId`,** in the original sketch: zero hits across eight clients, two protocol libraries
  and the vendor web UI. It survives in EVOK's documentation and in no client.
- **Per-connection scoping for the whole flag set** — only `emitLegacyDevNames` plausibly needs it, and
  per-connection state that changes payload shape is the bug class behind EVOK's WS filter.
- **A generic `compat.level` (`strict` | `fixed`)** — bundles unrelated choices, so a client needing one
  bug-compatible shape silently gets the other four.
- **Authenticating the compat surface** — it would break every existing client and defeat the project's
  reason to exist.
- **Any `:80` arrangement other than the stock site.** Our own listener fronting both surfaces, serving
  the SPA through nginx, or putting `api-compat` on `:80` directly all fail on the same three counts:
  they collide with the stock evok site (two servers claiming `default_server` means nginx will not
  reload), need root or `CAP_NET_BIND_SERVICE`, and either put the unauthenticated and privileged
  surfaces behind one origin — the separation G-2 keeps — or require a generated site file on every
  greenfield box, which is finding 4.7.
