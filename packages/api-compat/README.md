# `@evok-node/api-compat`

Byte-compatible with EVOK 3.0.6 for real clients. Permanent, first-class, never deprecated (G-3).

Owns **the** projection table, derived from driver introspection rather than hand-maintained.
EVOK's vocabulary meets ours here and nowhere else. Requires **at most one** onboard driver — zero is
the Gate, which must serve an empty API rather than erroring.

It can only emit what its table describes, which is why a `system` driver cannot reach this surface even
when an administrator lists it.

**Must not depend on:** any driver, `main`, `api-nextgen`, or anything carrying our groups, labels or
ordering — that absence is what makes G-3 a missing graph edge instead of a review rule.
