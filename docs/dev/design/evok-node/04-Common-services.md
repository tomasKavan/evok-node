# 04 — Common services

> **Memo, not content.** What belongs in this file, and what it gets written from. Written during
> [M3](../plan/roadmap.md); do not implement against a memo.

**Job:** the shared runtime a module may rely on — everything that is not messaging (03), config (02)
or the KV-store driver (06).

**This file is filled in on demand.** An entry appears here only once a **second** file needs it; one
caller is not a common service. Expect it to be the last of these files to settle.

**Covers (provisional)**

- **Logging:** levels, structure, correlation with message envelopes, per-instance scoping. The
  standards 12 and 18 will cite rather than restate.
- **Time and scheduling:** why scan work must not use raw `setInterval`, and what it uses instead.
- **Deadlines and cancellation** as a first-class concept, shared with 03.
- **Metrics and health reporting.**
- **Diagnostics:** dumping a module's view of the world on request, which is what makes support
  possible.

**Inputs:** research/08 · whatever 06–20 turn out to demand

**Open:** whether logging is large enough to deserve its own file. If 12 and 18 both need a page of
it, it is not a common-services entry any more.
