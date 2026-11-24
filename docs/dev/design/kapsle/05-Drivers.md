# 05 — Drivers

## 1. Scope

What every driver must be, whatever it talks to — the obligations that hold regardless of transport. The concrete shape 01 §6 and 03 §5 leave open — how a driver actually builds and maintains its introspection table and binds endpoints to addresses — is 05a's (`driver-kit`), the package most drivers build on. It assumes 01's two-kind model, 02's lifecycle and reload machinery, 03's envelope/addressing/introspection schema, and 04's common services; it does not restate them. 07 onward specialise this per transport class — Modbus, 1-Wire, the filesystem — and are the only place a transport's own data types belong.

## 2. What a driver is, and what it must never do

Three obligations, unconditional:

- **Never blocks the caller past its own answer.** A slow driver is a wedged driver, never proof the bus was slow this once (01 §8) — every wait already races a `Deadline` (04 §6).
- **Never throws across the boundary.** Expected failure is a `Response` value (03 §7) — for a `method` endpoint specifically, `onCall`'s own `CallOutcome` (05a §3.5) is how a handler produces one; a throw that escapes a handler is a bug driver-kit's dispatcher catches and reports as `internal-error`, never something a caller has to guard against.
- **A `reading`'s `GET` answers from memory, never from a live bus read.** This is what makes a timeout honest — the driver is genuinely wedged, not the bus slow this once. `CALL` is the deliberate exception: a method is an action, not a snapshot of held state, so touching the live device is the entire point of one. (`SET`'s own answer is always its declared type — `T`, or the narrower `TSet` when one's declared — never ambiguous; 05a §3.1/§3.5 have the mechanism.)

**"No value yet" is not "value 0."** An endpoint nothing has read yet must be representable as such, never defaulted quietly to zero or false — whatever the reading's value type is. A driver that tracks staleness (§4's scan loop is the common case) could make `readAt`/`stale` part of that value type itself — the driver's own discretion, not a field every reading carries. A client that can't tell "never read" from "read as zero" will eventually act on the wrong one; this is the failure mode research/04 documents repeatedly.

## 3. Lifecycle

Thin, deliberately: `configure`/`start`/`drain`/`stop` are 02 §4's, the two-phase startup barrier is 03 §9's. What this section adds is specific to a driver — what happens *inside* those calls is its own business (open a connection in `configure`, release it in `stop`), and there is no separate handshake/identify stage: whatever a driver needs to trust its own state before answering a request happens inside `configure`/`start` as ordinary logic, not a new lifecycle primitive.

`prepareReload` matters to exactly the drivers §7 is about: one holding something exclusive — a shared transport it arbitrates for others, a lock, a namespace — implements it to release precisely what the next config won't need, before commit ever begins. 02 §5.1 and 03 §9 already guarantee that ordering; this section only says which drivers need to act on it.

## 4. The scan loop — a best practice, not a contract

The right shape for a request/response bus with no push mechanism of its own — most of Modbus, most sensors — never a rule every driver must follow. A driver talking to something event-native has no scan loop and is not in violation of anything by lacking one.

Where a scan loop does apply, cadence, prioritization between fast and slow channels, and what falls behind first under load are guidance, not requirements this file enforces: `scheduleRepeating` (04 §5.2) with an explicit `overrunPolicy` is the mechanism; which channels get `'skip'` versus `'coalesce'`, and in what order a scan pass visits them, is each driver's own judgment about its own device. Reporting degradation, however it's reached, is `$health` (03 §3) — consumed like any other address, by whoever subscribes.

## 7. Sharing a driver-owned resource

01 §7's pattern, restated at the level a driver author actually acts on it: a resource one driver owns — a transport, a namespace — can be shared by other drivers that reach it through the owner's own request/response messaging, never by opening a second client on it themselves. The owning driver's own config says nothing about this on a dependent's behalf; the dependent declares the link itself (02 §4, 03 §8), and its own config carries whatever extra context the relationship needs — its address on that transport, say.

What the owner exposes for this is, so far, one recurring shape: a set of `CALL` endpoints mirroring the underlying protocol's own operations one-to-one, each declared with whatever `effect` that operation actually has — so a dependent can speak the protocol directly rather than the owner having to anticipate every device that might ever share it. 07 has the concrete shape for Modbus: eight methods, one per function code, rather than a single generic query/command pair — precise enough that a caller picks the exact wire operation instead of the transport guessing.

## 8. REMOVED
