# Modbus driver rules

Binding inside `modbus` and inside any driver whose transport is Modbus. Cite as **RPG-DMB-N**. Scope
and citation convention: [`README.md`](README.md).

These are in addition to [`drivers.md`](drivers.md), which applies to every driver regardless of
transport.

**RPG-DMB-1 — A multi-register value lies wholly inside one register block, read at one frequency.**
A 32-bit value split across two blocks, or across two reads at different rates, is read torn: half of
it is from one bus transaction and half from another. Checked when definitions load; a definition that
breaks this is **rejected, not repaired** — silently regrouping the blocks would hide a bad definition
behind a value that is usually right.

*Moved 2026-08-16 from `code.md`, where it was RC-19. Substance unchanged.*
