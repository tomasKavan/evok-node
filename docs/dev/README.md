# evok-node for developers

TODO - high level description of the package (not repeat whats in root README, look from different perspective, technically explain main features). Other important - tech stack, maintainer, agentic work info for humans, 

TODO - ??How to read docu??

## Working with this package and repo/git

TODO - download, install, build, test, run

## Architecture, coding basics and rules

## Documentation 

### Documentation layout

1. **[`plan/`](plan/README.md)** — where the work actually is. [`STATUS.md`](plan/STATUS.md) first, then
   [`roadmap.md`](plan/roadmap.md) for the milestone it sits in.
4. **[`design/`](./)** — **the design, and what you implement against.** Start at
   [`00-Intro.md`](dev/00-Intro.md) if you are new, then the file for the area you are touching.
5. **[`research/`](research/README.md)** — the input `dev/` was written from, never a substitute for it.
   [`to_revision/`](research/to_revision/README.md) is the laboratory: the former ADRs, binding on
   nothing, each worked into `dev/` if accepted.
6. **[`modbus-reg-map/`](modbus-reg-map/README.md)** — official Unipi register maps. Ground truth,
   read-only, no prose.

### Citing



This file is a **map**: where things are, how to cite them, and which one wins. What each document must
*contain* is RD-2, and how to write one is the rest of [`rules/docs.md`](rules/docs.md) — so the list
below says where to go and in what order, not what belongs in each file. The precedence chain at the
bottom is the one normative thing this file owns; everything else here only points.

## Layout, in read order

1. **[`plan/`](plan/README.md)** — where the work actually is. [`STATUS.md`](plan/STATUS.md) first, then
   [`roadmap.md`](plan/roadmap.md) for the milestone it sits in.
2. **[`GOALS.md`](GOALS.md)** — read before arguing that anything is in or out of scope.
3. **[`rules/`](rules/code.md)** — binding, and mostly CI-enforced: [code](rules/code.md) ·
   [packages](rules/packages/README.md) · [testing](rules/testing.md) · [docs](rules/docs.md) ·
   [git](rules/git.md).
4. **[`dev/`](dev/README.md)** — **the design, and what you implement against.** Start at
   [`00-Intro.md`](dev/00-Intro.md) if you are new, then the file for the area you are touching.
5. **[`research/`](research/README.md)** — the input `dev/` was written from, never a substitute for it.
   [`to_revision/`](research/to_revision/README.md) is the laboratory: the former ADRs, binding on
   nothing, each worked into `dev/` if accepted.
6. **[`modbus-reg-map/`](modbus-reg-map/README.md)** — official Unipi register maps. Ground truth,
   read-only, no prose.

## Citing a rule

Always with its prefix, never as a bare number. Grep the prefix to find the rule — it is written at
the rule itself, not only in this table.

| Prefix | Source | Example |
|---|---|---|
| **G-N** | [`GOALS.md`](GOALS.md) invariants — scope and architecture | G-5 |
| **RCD-N** | [code rules](rules/code.md) — how we write TypeScript, nothing project-specific | RCD-2 |
| **RPG-\<SCOPE\>-N** | [package rules](rules/packages/README.md) — binding only inside the packages the file names | RPG-DRV-1 |
| **RT-N** | [testing rules](rules/testing.md) | RT-1 |
| **RD-N** | [docs rules](rules/docs.md) | RD-2 |
| **RG-N** | [git rules](rules/git.md) | RG-7 |
| **RPL-N** | [plan rules](plan/README.md) — how the plan is maintained | RPL-1 |
| **R04-N** | [`research/04`](research/04-known-bugs-and-lessons.md) design rules — evidence, not policy | R04-23 |
| **GOALS §Section** | a binding statement in [`GOALS.md`](GOALS.md) that is not a numbered invariant | `GOALS §Hardware scope` |

`docs/dev/` has **no prefix and no numbered rules** — it is design, not policy. Cite it by file and
section: `dev/03 §2`. If something in there deserves to be binding, it becomes a rule in
[`rules/`](rules/code.md) or an invariant in [`GOALS.md`](GOALS.md); it does not become a dev-doc rule
number.

Numbers are stable: **append, never renumber.** A rule that becomes wrong is superseded in place, with
a note saying by what. This holds for every prefix in the table.

**Not a prefix.** `ADR-NNNN` no longer cites anything. The set was dissolved rather than re-locked:
the design and its reasoning live in `dev/`, and the files under
[`research/to_revision/`](research/to_revision/README.md) are proposals. Cite one as a research path —
`research/to_revision/0010 §Decision` — never as authority.

`ADR-NNNN` citations survive throughout `docs/research/`, which is permanent and corrected only with a
dated note (RD-7), so they are not being swept. Resolve one by reading the file it names: if `dev/` has
since decided the question, the dev doc wins; if not, it is still an open proposal. A citation *outside*
`docs/research/` is a bug — report it or fix it.

**Stale prefixes.** `RC-N` is now `RCD-N` and `RP-N` is now `RPL-N`. `RC` numbers were
**regenerated**, not just re-prefixed, so an old `RC-17` is not today's `RCD-17` — there is no
`RCD-17`; that rule is now `RPG-DRV-1`. Treat any surviving `RC-N` citation as stale and resolve it by
reading the rule.

**Stale milestone tokens.** Milestones are `MN`, defined in [`roadmap.md`](plan/roadmap.md).
research/11, research/12 and research/15 use `M0`–`M6` and `N0`–`N10` from the superseded roadmap —
those are **not** today's milestones. Resolve such a token inside the research file that uses it, never
against `roadmap.md`.

## Precedence

**G wins over everything.** Then the rules files, then **`dev/`**, then research. This file loses to
all of them; it only points.

**`dev/` outranks the code.** It is the design, not a description of what got built: code that
contradicts it is a defect in the code. Changing the design is a human decision, and RD-8 says how.

**`dev/` outranks `research/`.** Research is the source material a dev doc was written from, and a dev
doc is allowed to overrule it — a design decision may reject, narrow or reinterpret a research
finding, and that is the decision, not an error. So where the two disagree about *what we build*,
`dev/` wins. Where they disagree about *what EVOK or the hardware does*, that is a factual claim and
research wins — the dev doc is wrong and gets fixed. RD-8 requires a deliberate departure to be marked
and linked, so that nobody later "fixes" it back.

If research and reality disagree, **reality wins** — and you fix the research file in the same PR,
with a dated correction note (RD-7).

A rule stated in two places is a bug (RD-6).
