# `fixtures/generated/` — read-only

Derived from `docs/modbus-reg-map/` by a committed generator. Address tables for every model ×
section in the corpus, codec golden tables.

**Never edit a file here — [RT-1](../../docs/rules/testing.md).** If a test fails against one of
these, the code under test is wrong, or the generator is wrong. Fix the generator and regenerate.

Why these are the primary safeguard rather than a supplement: no purchasable Unipi device has more
than 16 channels of one type in a single section, so the worst bug in the upstream corpus — silently
driving the wrong relay — can never be reproduced on hardware we can buy.

Empty until M1.
