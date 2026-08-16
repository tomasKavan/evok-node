# Driver rules

Binding inside every driver package and `driver-kit`. Cite as **RPG-DRV-N**. Scope and citation
convention: [`README.md`](README.md).

All three rules below moved from `code.md` on 2026-08-16, where they were RC-17, RC-20 and RC-18.
Substance unchanged except where noted.

**RPG-DRV-1 — Never derive an identity from a loop counter.** An address comes from the one audited
address function, which holds the bank stride and the bit mask in exactly one place. A channel index
that happens to equal a loop variable is a coincidence, and it stops being true the moment a model has
a gap, a reserved channel or a differently sized bank. Every upstream failure of this kind is in
[research/04](../../research/04-known-bugs-and-lessons.md).

**RPG-DRV-2 — Every reading carries `value`, `readAt` and `stale`.** No silent zeros, and no value
that stays frozen without saying so. A reading whose age is unknown is not a reading.

`value` may be a structure, not only a scalar.

*Moved 2026-08-16.* The rule previously went on to argue what this implies for the project's data
categories. That is a design conclusion, not a rule, and belongs in the development documentation.

**RPG-DRV-3 — A duplicate endpoint id, or two endpoints landing on the same coil or (register, bit),
is a fatal startup error.** Not a warning, not a log line, not last-writer-wins. Checked at init
against the driver's own address tables, and fatal every time.

This is the assertion that catches a wrong address table before it drives the wrong relay, and it is
the *only* check that can — no purchasable Unipi device has more than 16 channels of one type in a
single section, so the bank-stride half of that bug class can never be reproduced on hardware
([research/10 §4](../../research/10-test-kit.md)). RPG-DRV-1 keeps the arithmetic in one place;
this rule proves the arithmetic came out injective. Its test half is RT-3.

A driver checks only itself. Addresses are driver-qualified, so uniqueness is local and needs no
global view — a driver that has to ask another driver what it owns has the wrong boundary.

*Restored 2026-08-16 as RPG-DRV-3*, having been dropped for one commit. Its second half — the same
check as injectivity of a projecting API's table, which is fatal at API start but must **not** kill a
running API when a hot-plugged device collides later — is an API rule and is deliberately not stated
here. It belongs with the projection design; write it down when that lands.
