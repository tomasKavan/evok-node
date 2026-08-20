# 00 — Intro

**Job:** orient someone about to design or implement part of evok-node.

This **is not** an introduction to the project 
* the root [`README.md`](../../README.md) does that for outsiders, 
* [`CLAUDE.md`](../../CLAUDE.md) for agents/people working/coding here, and 
* [`GOALS.md`](../GOALS.md) for scope. 

This **is**

* an introduction to **the design**: why the thing exists in this shape, and the constraints every file
  from 01 on is already committed to;
* **authoritative over the code.** No code may contradict this design. Where the design turns out to be
  wrong, the design changes first, and a human approves it (RD-8).

## Why we replaced EVOK rather than patched it

EVOK works. It runs on thousands of installations and it is the reason Unipi hardware is usable from
anything that speaks HTTP. Structurally it is thin: a Modbus **client** with an HTTP and WebSocket
surface on top, reaching onboard I/O over Modbus TCP to a local server — `unipitcp` on `127.0.0.1:502`
on the PLC families, `unipi-one-modbus` on `50200` on Unipi 1.1 — and extensions over RS-485
([research/02](../research/02-hardware-model.md)). Patching it would have been much cheaper than
replacing it, and we did not.

The reason is the *shape* of its defect tail, not its size. Read the 29 findings in
[research/04](../research/04-known-bugs-and-lessons.md): they are dominated by **state** problems rather
than by algorithms computing wrong answers. Discovery runs once at startup, so a slave powered on a
minute later never appears. A register cache is shared between two slaves because a `copy()` should have
been a `deepcopy()`. One unreachable slave blocks *every* bus and every client — not just its own —
because the I/O runs in the WebSocket handler, and on recovery the backlog replays stale commands onto
physical outputs. A 32-bit counter is read torn across two register blocks. Closing the last WebSocket
stops the polling loop for devices configured `scan_enabled: false`.

Algorithm bugs are local, and you patch them. State problems *are* the architecture, and each patch
narrows one symptom while the cause keeps generating new ones — which is what a decade of EVOK's commit
history records. Its own maintainers' open issues read as a hardening to-do list, and that is the
strongest available evidence that what remains is structural rather than a backlog of mistakes.

There are arithmetic bugs too — finding 1.1's bank stride, finding 3.8's conversion formulas — and they
matter enormously; the second constraint below is about one of them. The claim is about where the
*tail* lives, not that the corpus contains no wrong sums.

So the interface is inherited and the design is not. Clients cannot tell the difference — that is what
G-3 buys them — and everything behind the interface is ours to shape so that these failures are not
representable in the first place.

## The design frame

Five constraints shaped every file from 01 on. None of them is new here, and each cites where it is
actually binding. They are collected because a designer who meets one of them for the first time in
file 09 has already designed around it wrongly.

1. **The compat surface is permanent, and leaks nothing** (G-3). It is a flat projection of our model,
   never a shape we design toward. Enforcement is a *missing* edge in `.dependency-cruiser.cjs`:
   `api-compat` imports nothing that could carry our groups, labels or ordering, so a leak is a build
   failure rather than a review comment.
2. **Half the worst bug class cannot be reproduced on hardware we can buy** (RT-3, RPG-DRV-3, and
   [research/10 §4](../research/10-test-kit.md)). Finding 1.1 silently drives the **wrong relay**, by two
   mechanisms. The `start_index` half *is* reproducible, on the L527's section 3 with a deliberately
   split definition through the RO→DI loopback. The missing-bank-stride half needs more than 16 channels
   of one type in a single section, and **no purchasable Unipi device has that** — so it is unverifiable
   permanently, not merely until we buy something. For that half, generated address tables and a
   fatal-on-duplicate assertion are not belt-and-braces; they are the entire safeguard. A design whose
   correctness cannot be checked by a generated artefact is not finished.
3. **The driver↔API boundary must survive serialisation** (G-1). One process for now, but everything
   crossing that boundary is data: no callbacks, no class instances, no Buffers, no shared mutable
   state. Getting it wrong costs nothing at runtime and makes the later split a rewrite, which is why it
   binds before the feature that needs it exists.
4. **Four kinds of data, four lifecycles** (G-5). Config, user data, platform facts and readings differ
   in who may write them and when they may change. Conflating the first two is exactly where EVOK's
   alias handling failed.
5. **Two component kinds, and no third.** Drivers act, APIs query, `main` orchestrates and sits on no
   request path; anything that looks like a third kind is a driver whose transport is not Modbus. Stated
   properly in [01](01-System-architecture.md), with the enforceable form in `.dependency-cruiser.cjs`.

## Reading paths

[`docs/README.md`](../README.md) has the read order for the repository. These are the paths through
*this* directory, and each assumes you have read `GOALS.md` and the rules first.

| If you are | Read |
|---|---|
| new here | this file · 01 · 03 · 06 · 13. Concepts only — stop before the concrete drivers |
| writing a driver | 06 · 07 if the transport is Modbus · the file for that driver · 03 for the contract · [`rules/packages/drivers.md`](../rules/packages/drivers.md) |
| writing an API | 13 · 03 · then 14 or 15 · 05 for what you may reuse |
| fixing a compat bug | 14 · `COMPATIBILITY.md` · [research/01 §9](../research/01-evok-api-surface.md) · [research/07](../research/07-client-compatibility.md) · the golden transcript for that route |
| adding a model | `GOALS §Hardware scope` first, to confirm it is in scope · 07 · [research/06](../research/06-register-maps.md) · the model's maps under [`docs/modbus-reg-map/`](../modbus-reg-map/README.md) |

## Where decisions live

**Here.** A dev doc carries the design *and* the reasoning that produced it — what was rejected, which
research finding was narrowed and to what, what is still TBD. RD-8 is the rule for writing that, and it
is also what makes these files rank above the code (precedence: [`docs/README.md`](../README.md)).

There is deliberately **no ADR directory**. The set that existed until 2026-08-18 was dissolved rather
than re-locked, because a decision recorded both in an ADR and in the dev doc that implements it is
recorded twice, and two copies drift (RD-6). The fourteen files under
[`research/to_revision/`](../research/to_revision/README.md) are what survived: proposals, binding on
nothing, each owed an answer by a named file here. Its index says which file owes what, and that index
is how M3 knows when it is done.

**Rejected:** keeping ADRs for the residue no single dev file owns. Only two of the fourteen were in
that class, and both landed better elsewhere — hardware scope in `GOALS §Hardware scope`, instrument
independence as RT-15 — which would have left a whole documentation kind maintained for a case that had
stopped existing.

The cost is real and belongs on the record: with no immutable set, the only thing stopping a later
rewrite from quietly erasing a rejected alternative is RD-8's prohibition on deleting reasoning, and
that is prose rather than a lint rule. If that prohibition turns out not to hold in practice, this is
the decision to revisit.

## Open

**TBD — what can a reader expect to actually work at 1.0?** *What 1.0 is* is still TBD in
[`GOALS.md`](../GOALS.md), and M3 settles it. Specifically unanswered: which of the five in-scope
hardware families must be verified rather than merely map-driven; whether the compat surface alone is
enough to ship, or the nextgen API and the inspector UI are part of 1.0; and whether the two families
with no hardware (`GOALS §Hardware scope`) can be claimed on simulator evidence alone. This file gains
one line when that is settled, because it is the first question a new contributor asks — and today the
honest answer is "read [`STATUS.md`](../plan/STATUS.md)".
