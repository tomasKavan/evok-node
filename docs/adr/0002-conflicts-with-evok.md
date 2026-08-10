# ADR-0002 — `Conflicts: evok`, with shared OS dependencies declared by us

- **Status:** Accepted — dependency list pending the capture trip
- **Date:** 2026-08-10
- **Refs:** docs/GOALS.md §The drop-in guarantee, invariant 7 · docs/research/05-evok-node-design-notes.md §7.2 · docs/research/10-test-kit.md

## Context

research/05 §7.2 deferred "whether we can `Conflicts: evok`". The deciding fact is not packaging
policy: **two processes cannot both own `/dev/ttyNS0`.** research/10 already requires
`systemctl disable --now evok unipitcp` merely to free the buses for the test rig. So evok and
evok-node can never usefully run at the same time, and "coexistence" could only ever mean *installed
together, exactly one running* — a state whose only benefit is a faster rollback.

The alternative considered was installing alongside and disabling evok in `postinst`. That stops a
running control system during `apt install`.

## Decision

`Conflicts: evok`. The two cannot be installed simultaneously. Rollback is `apt install evok`.

**We declare the shared OS dependencies ourselves** — `unipi-kernel-modules` and whatever else the
capture trip shows evok pulls in. Otherwise removing evok can autoremove the packages our own
runtime and migration depend on.

`apt remove evok` leaves `/etc/evok/*` (conffiles) and `/var/lib/evok/alias.yaml` (runtime state,
outside dpkg's remove scope) intact, so ADR-0003's migration still has its inputs afterwards.
`apt purge` destroys both, so the documentation says plainly: **migrate before purging.**

## Consequences

Makes easy: predictable installs; no surprise service stops; a rollback that restores the previous
system exactly, because `/etc/evok` was never touched.

Makes hard: trialling evok-node with a fast switch back — the operator removes evok first. Accepted;
the tty exclusivity means the switch was never going to be fast anyway.

**Blocked on the capture trip.** The exact `Conflicts:`/`Depends:`/`Replaces:` set and the handling
of evok's nginx `:80` site file cannot be written until we have `apt-cache show evok`,
`dpkg -L evok`, its systemd unit names and that site file. Two nginx sites claiming
`default_server` means nginx will not reload, so this is a real conflict and not a detail. Recorded
in `plan/STATUS.md` as a blocked item on the same trip as the golden transcripts.

**Compensating control:** GOALS invariant 7 — startup preflight refuses to run, naming the conflicting
unit, if evok or `unipitcp` holds the ttys. That covers the case where someone defeats the packaging
by installing from npm rather than the `.deb`.
