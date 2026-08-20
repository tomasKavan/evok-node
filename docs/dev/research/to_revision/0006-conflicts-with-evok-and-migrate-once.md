# ADR-0006 — `Conflicts: evok`, and EVOK's config is migrated once by a separate tool

- **Status:** Proposal, **not in force** — the set was dissolved 2026-08-18, see [README](README.md). Was: Accepted — dependency list pending the capture trip.
- **Date:** 2026-08-10
- **Refs:** docs/GOALS.md §The drop-in guarantee, G-5, G-7 ·
  docs/research/05-evok-node-design-notes.md §7.2 · docs/research/03-config-and-hw-definitions.md
  §1, §3 · docs/research/10-test-kit.md · ADR-0005

## Context

**Two processes cannot both own `/dev/ttyNS0`.** research/10 already requires
`systemctl disable --now evok unipitcp` merely to free the buses for the test rig, so evok and
evok-node can never usefully run at the same time; "coexistence" could only mean *installed together,
exactly one running*, whose only benefit is a faster rollback.

The config question is separate but lands in the same place. An earlier design had the daemon read
`/etc/evok-node/config.yaml` if present and otherwise fall back to `/etc/evok/config.yaml` plus
`/var/lib/evok/alias.yaml`. That puts EVOK's formats and their traps — the `autogen.yaml` deep-merge,
the alias file silently yielding `{}` for any unexpected `version` (the docs' own example writes
`version: 2.0` unquoted, which YAML parses as a float), the non-atomic writes — permanently inside the
daemon's startup path, and creates precedence logic whose failures are undiagnosable in the field.
"Which file won?" is exactly the class of question research/04 §4.6 shows Unipi's support load is made
of. Aliases are also mutable through the API, so a fallback needs a write policy: write into
`/var/lib/evok/alias.yaml` and we mutate another package's state, breaking clean rollback; write to our
own store and the two sources diverge silently.

## Decision

**`Conflicts: evok`.** The two cannot be installed simultaneously. Rollback is `apt install evok`.
**We declare the shared OS dependencies ourselves** — because otherwise removing evok can autoremove the
packages our own runtime and migration depend on.

**Correction, 2026-08-13.** This previously named `unipi-kernel-modules` as the package at risk. Measured
on a Patron: `evok` declares `Depends: python3` and nothing else, so removing it cannot autoremove the
kernel modules. The package that **is** taken is `nginx` — `apt-get -s remove --auto-remove evok` removes
`evok`, `evok-web`, `nginx` and `nginx-common`, and ADR-0009 keeps nginx as the front end. So
`Depends: nginx`, and the list is that plus whatever the systemd and nginx-site facts add. `evok-unipi-data`
survives the removal and is **not** a dependency of ours — ADR-0014 removed the reason to want one.

**A one-shot migration tool**, run explicitly by the operator or by packaging, **never by the
daemon.** It reads `/etc/evok/config.yaml` and `/var/lib/evok/alias.yaml` and writes
`/etc/evok-node/config.yaml` plus `driver-store`'s database (ADR-0005). After that the two
installations share no state. That the migrator, not the daemon, writes the config file is what keeps
ADR-0005 and G-5 absolute: if no config exists the daemon reports that and exits non-zero naming what
to do, rather than helpfully generating one. The tool accepts explicit input paths so it can run
against a backup, and warns — at a moment a human is watching — about anything it cannot represent.

**The daemon has no knowledge of EVOK's config or alias formats.** That knowledge lives only in the
migration tool.

**Greenfield installs do not depend on the migrator.** A machine that never ran EVOK has nothing to
migrate, so packaging ships a **default config as a conffile**. `/etc/evok` is never read and never
written: the hardware definitions and the inventory are ours (ADR-0014).

**Correction, 2026-08-13.** This previously ended "`autogen.yaml` and `hw_definitions/*.yaml` remain
runtime daemon inputs read from the OS image (ADR-0007)". They do not. Both are ours, which is also what
makes the greenfield case work at all — `evok-unipi-data` is built per product, and `apt purge evok` was
never the only way to end up without those files.

## Consequences

Makes easy: predictable installs, no surprise service stops, and a rollback that restores the previous
system exactly because `/etc/evok` was never touched. A strict, versioned, single-source config schema
that is ours alone. And testing: the migrator is a pure function `(evok config, alias file) → (our
config, store)` with golden fixtures from the capture trip.

Makes hard: trialling evok-node with a fast switch back — the operator removes evok first. Accepted;
tty exclusivity means the switch was never going to be fast. Nothing at runtime; the cost is one more
artefact and a documented operator step.

**Ordering trap.** `apt remove evok` leaves `/etc/evok/*` (conffiles) and `/var/lib/evok/alias.yaml`
(runtime state, outside dpkg's remove scope) intact, so migration still has its inputs. **`apt purge`
destroys both,** hence the standalone tool and the documented **migrate before purging**.

**Blocked on the capture trip.** The exact `Conflicts:`/`Depends:`/`Replaces:` set and the handling of
evok's nginx `:80` site file need `apt-cache show evok`, `dpkg -L evok`, its systemd unit names and
that site file. Two nginx sites claiming `default_server` means nginx will not reload, so this is a
real conflict and not a detail (ADR-0009). Recorded in `plan/STATUS.md`.

**Compensating control:** G-7 — startup preflight refuses to run, naming the conflicting unit, if evok
or `unipitcp` holds the ttys. That covers someone defeating the packaging by installing from npm.

**Rejected:**

- **Installing alongside and disabling evok in `postinst`** — it stops a running control system during
  `apt install`.
- **Runtime fallback with per-concern source flags.** It was the original design; it loses on
  diagnosability and permanently couples the daemon to a format we are replacing.
