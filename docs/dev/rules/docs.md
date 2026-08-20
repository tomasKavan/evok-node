# Documentation rules

**RD-6 — Prohibited.**

- Restating a type signature in prose.
- Documenting features that do not exist yet **as though they exist**. Aspirational docs are lies with
  a delay. Two exceptions, both of which must label what they are: `GOALS.md`, which might state post-1.0 direction as direction and never as behaviour; and `docs/dev/`, whose whole job is to describe a design before it is built (RD-8).
- Tutorials before `0.1.0`. The API will move.
- A `docs/` file that duplicates a research file — link it instead.
- Restating a rule that already has a number. Cite it.
- Emoji, decorative headings, and "Overview" sections that overview nothing.
- Marketing tone. This is an industrial control library; the audience wants precision.

**RD-7 — Research follows different rules.** `docs/research/` is not user documentation; it is our
knowledge base about EVOK and Unipi hardware — cited, evidence-marked, permanent. Completeness beats
brevity there, because its job is to stop us re-deriving hardware behaviour. Corrections are **dated
and marked**, never silent edits; see `research/02-hardware-model.md` §3.3 for the format.

**RD-8 — `docs/dev/` is design, and follows different rules.** It describes the system as designed,
which means it legitimately runs ahead of the code — the RD-6 exception exists for exactly this. The
precedence **ordering** is stated once, in [`docs/README.md`](../README.md) — do not restate it
elsewhere.

- **No rule numbers.** How to cite one, and what to do with something that should be binding, is in
  the citation section of [`docs/README.md`](../README.md).
- **Every departure from research is marked and linked.** A dev doc may reject or narrow a research
  finding; one that does so silently is indistinguishable from one that got it wrong.
- **Unsettled means TBD, with the question written out.** An unmarked guess reads as a decision, and
  will be implemented as one.
- **Say what was rejected and why.** That is the part nobody can reconstruct later, and the reason
  these files exist rather than just the types.
- **The design is authoritative over the code.** Code that contradicts a dev doc is a defect in the
  code, not a fact the doc has to accommodate. An agent may not settle the conflict by writing the code
  it prefers and amending the doc to match — that is the failure this rule exists to prevent, because
  it looks identical to progress. Where the design turns out to be wrong, the dev doc changes **first,
  and by human decision**: the change may ship in the same PR as the code (RD-5), but it is stated in
  the PR body under its own heading, and approving that PR is what approves the new design (RG-6).
- **A reversal leaves a dated line.** When a dev doc replaces a design it previously stated, an
  append-only footer records it: date, what it was, what it is, why. One line. Nothing else in `dev/`
  keeps that history.
- **A smoothing pass may not delete reasoning.** RD-5's alpha and beta passes may rewrite any prose
  here, but rejected alternatives, departure markers, TBDs and reversal lines are not theirs to remove.
  Coherence is precisely the argument for removing them, and they are why these files exist rather than
  just the types.
