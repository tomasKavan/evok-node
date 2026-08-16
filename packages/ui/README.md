# `@evok-node/ui`

Compact status display with filter, sort and search; control and configuration; status rendered on PLC
layout drawings. A replacement for `evok-web-jq`, not a port of it.

Renamed from `inspector` (2026-08-12) because `inspector` and `introspect` were one letter apart, one a
package and the other the load-bearing message op.

Built independently and served from a packaging path, so **nothing imports it** and `api-nextgen` gains no
edge to a UI package. Single-instance by construction; G-4's aggregation case is client-side user data or
a separately deployed SPA with `ui: false`.

**Must not depend on:** any driver, any api, `main`. Public API only. Whether it may consume `client` is
still open.
