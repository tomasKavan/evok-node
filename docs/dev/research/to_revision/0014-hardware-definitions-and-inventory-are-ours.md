# ADR-0014 — Hardware definitions and inventory are ours; nothing is read from `/etc/evok`

- **Status:** Proposal, **not in force** — the set was dissolved 2026-08-18, see [README](README.md). Was: Accepted.
- **Date:** 2026-08-13
- **Supersedes:** ADR-0007
- **Refs:** docs/plan/hw-definition-format.md (the format itself) · docs/GOALS.md G-5, G-3 ·
  docs/research/03-config-and-hw-definitions.md §2, §4 ·
  docs/research/05-evok-node-design-notes.md §2.5, §8.5 ·
  docs/research/06-register-maps.md §2, §2.2, §2.7 · ADR-0005, ADR-0006, ADR-0008, ADR-0012

## Context

ADR-0007 made `/etc/evok/hw_definitions/*.yaml` the base layer and promised "the base layer alone is
always sufficient". Measured on a Patron in August 2026, that promise does not hold:

- Those files belong to **`evok-unipi-data`**, a package built **separately per product** — the unit
  carried `1.1.2~bookworm-patron`. Content is therefore not identified by name and version, so we cannot
  pin, test against, or fingerprint the layer we were treating as ground truth.
- It is mutually exclusive with `evok-unipi-data-full` (unversioned `Breaks:`, no `Provides:`), so a
  `Depends:` from us could be satisfied by *removing* the larger corpus.
- The installed corpus does not contain every model its own tooling asks for: `60-evok-autogen.sh`
  resolves `UNIPI11`, `UNIPI11LITE`, `EMO-R8` and Iris card models that the Patron build does not ship.
- ADR-0006's `Conflicts: evok` plus `apt purge`, and greenfield installs, both leave `/etc/evok` absent.

Independently, ADR-0012 already generates `(model, section, kind, channel) → (register, bitOffset, coil)`
from the register-map corpus for **more** models than `evok-unipi-data` ships. Consuming Unipi's YAML at
runtime therefore meant the daemon ran on one ground truth while CI asserted against another.

## Decision

**We ship our own hardware definitions, in our own format, and read nothing from `/etc/evok` at runtime.
We depend on no Unipi data package.** Concretely:

1. **Two disjoint roots**, not layers: ours at `<pkg>/definitions/<transport>/<vendor>/<device>`, the
   operator's under `/etc/evok-node/hw_definitions/custom/…`. `custom` is a reserved first segment, so
   the namespaces cannot collide and no merge, precedence or per-field provenance exists. An id is the
   relative path; config names devices by id.
2. **Our own inventory generator** writes `/etc/evok-node/autogen.yaml`, from three entry points —
   os-configurator's `run.d` hook, our `postinst`, and a fingerprint check at daemon start. The hook fires
   only on hardware change, so it is a trigger over a standalone generator, never the mechanism. Reading
   `/run/unipi-plc/unipi-id/` ourselves keeps `unipi-os-configurator` an opportunity, not a requirement
   (research/05 §2.5, now the whole story rather than a fallback).
3. **Identity is checked against the board**, not assumed from config: `identifies.hardwareId` (holding
   1004) where we know the value, and the channel census (holding 1001/1002) everywhere. Either mismatch
   refuses to start, naming the unit — RS-485 has no discovery, so config is otherwise an unverified claim.
4. **Several definition files per model, each with a `minFirmware`**, resolved at handshake to the highest
   floor at or below the board's version. Compared as the raw uint16, because the human-readable form is
   hexadecimal.
5. **Written once, from two sources**: the register-map CSVs *and* EVOK's shipped `hw_definitions`. The
   latter is a prerequisite, not a nicety — the CSV exports carry AI/AO mode *registers* but not their legal
   values, and G-3 makes the enums mandatory because EVOK exposes mode switching. Every disagreement
   between the two sources is reported and resolved, not silently decided.
6. **ADR-0012's tables gain a second duty**: CI asserts that every address a definition resolves matches
   the table generated independently from the maps. ADR-0012 is immutable and unedited; the obligation is
   recorded here.

The format itself — envelope, features, encodings, modes — is specified in
[`docs/plan/hw-definition-format.md`](../13-config-and-hw-definition-format.md).

## Consequences

Makes easy: one ground truth with an automated check against it; a definition format carrying the fields
Edge needs (per-channel mode sets, census, conversion times) without a merge; a package that cannot be
broken by another vendor's upgrade cadence; and greenfield or post-`purge` installs that simply work.
ADR-0007's whole apparatus — overlay layer, three-layer merge, per-field provenance, `appliesTo`
fingerprints, warn-in-theirs/error-in-ours — disappears.

Makes hard: **the corpus becomes ours to maintain.** A new Unipi model needs a release from us rather than
an `apt` upgrade of somebody else's data package; that is the real price of the drop-in guarantee, and it is
paid knowingly. There is no regeneration script, so the transcription procedure is checked in to be
repeatable. Both derivations read the same CSVs, so a wrong CSV still passes both — narrowed, not closed, by
EVOK's definitions being a second opinion.

**Now owed.** The capture trip's copy of the stock `hw_definitions` is **blocking**: board `00` cannot be
written without its `modes{}`. Edge and Unipi 1.1 are not blocked, since their XLSX `Description` sheets
carry the enumerations (research/06 §2.7, §2.8).

**Rejected:**

- **`Depends: evok-unipi-data`** — the two-line fix. It works today, but pins us to a per-product package
  whose content its version does not identify, and which apt may satisfy with the smaller of two mutually
  exclusive variants.
- **Vendoring a verbatim snapshot of the stock definitions** — keeps EVOK's format and its trap list in our
  loader forever, and buys nothing over transcribing into a format that has the fields we need.
- **Keeping `/etc/evok/hw_definitions/` as an optional gap-filler** for models we lack — attractive, but it
  reintroduces the EVOK-format parser on a runtime path for a case that the `custom/` root already covers.
- **Generating definitions with a script** — rejected for a one-time transcription whose inputs are a PDF
  corpus, CSV exports of three different vintages and another project's YAML. The script would be written
  once, run once, and then have to be maintained as if it would run again.
