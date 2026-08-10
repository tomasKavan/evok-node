# `fixtures/generated/` — read-only

Derived from `docs/modbus-reg-map/` by a committed generator. Address tables for every model ×
section in the corpus, codec golden tables.

**Never edit a file here.** If a test fails against one of these, the code under test is wrong, or
the generator is wrong. Fix the generator and regenerate; the diff then shows up as intended output.
CI regenerates this directory and fails on any difference, so a hand edit cannot survive review.

These fixtures are the project's primary safeguard, not a supplement: no purchasable Unipi device
has more than 16 channels of one type in a single section, so the worst bug in the upstream corpus —
silently driving the wrong relay — can never be reproduced on hardware we can buy. See
[docs/rules/testing.md](../../docs/rules/testing.md) and `CLAUDE.md` rule 14.

Empty until M1.
