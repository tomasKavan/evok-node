# `@evok-node/client`

Reconnect, backoff and automatic resubscribe, so integrators stop reinventing it five different ways.

**Depends on nothing of ours yet.** It targets `api-nextgen`'s public schema, which does not exist until
N6; the edge is listed as undecided in `.dependency-cruiser.cjs` rather than guessed, because the
alternative — a separate `schema-nextgen` package — is a real option and picking one silently would settle
it. Decide when the schema lands.

**Must not depend on:** any driver, `main`, `modbus`, `hw-definitions`, `api-compat`.
