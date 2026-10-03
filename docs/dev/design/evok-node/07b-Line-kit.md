# 07b — Line-kit

## 1. Scope

`packages/line-kit` (`@evok-node/line-kit`). The shared byte-level transport underneath both `modbus-kit`'s RTU transport (07 §3) and `driver-dali`'s serial/TCP controllers (12 §4.1) — a serial port or a TCP socket, wrapped once, with one config shape and one reconnect policy, so neither package (nor a third one, later) reimplements `serialport`/`net.Socket` handling independently. It owns nothing about framing, correlation, or timing — that stays each consumer's own protocol, layered on top (Modbus's t3.5 pacing and per-line mutex stay in `modbus-kit`, §6; Foxtron's SOH/checksum/ETB framing stays in `driver-dali`, 12 §6). 07 §2's "wrap, don't reinvent" reasoning, generalized past Modbus and past serial alone.

## 2. Interface

```ts
// @evok-node/line-kit
type LineTransportConfig =
  | { kind: 'serial'; path: string; baudRate: number; dataBits?: 7|8; stopBits?: 1|2; parity?: 'none'|'even'|'odd' }
  | { kind: 'tcp'; host: string; port: number };

interface LineHealth {
  state: 'unknown' | 'connecting' | 'open' | 'reconnecting' | 'closed';
  consecutiveFailures: number;
  lastOpenAt: Millis | null;   // Clock's own scale (04 §4.1) — never a wall-clock Date; this is duration bookkeeping, not a display timestamp
}

interface LineTransport {
  open(): Promise<void>;
  close(): Promise<void>;
  write(bytes: Uint8Array): Promise<void>;
  onData(cb: (bytes: Uint8Array) => void): void;
  health(): LineHealth;
}

function createLineTransport(config: LineTransportConfig, deps: { clock: Clock; log: Logger }): LineTransport;
```

Whoever owns a `LineTransport` calls `open()` in its own `configure()` and `close()` in its own `stop()` — the same lifecycle split `ModbusTransport` already has (07 §4); this package has no lifecycle of its own beyond that.

`write`/`onData` move raw bytes only — no message boundaries, no correlation. A consumer that needs request/response matching (both current ones do) builds it on top, against its own protocol's own framing; this file has no opinion on where one message ends and the next begins.

## 3. Serial

`serialport`, wrapped, never used raw. What this package adds on top: the reconnect supervisor (§5) and one unified config shape, so a caller never touches `SerialPort`'s own constructor options directly. It does **not** add RX-flush-before-every-request, t3.5 pacing, or any other per-transaction behaviour — that stays `modbus-kit`'s own concern (07 §2), layered on this package's serial implementation as a subclass, not something every consumer gets whether it wants it or not.

## 4. TCP

A plain `net.Socket`. No framing assumptions — `driver-dali`'s Foxtron controller reads the identical ASCII byte stream over this as it does over serial (12 §6); Modbus TCP's own MBAP framing is already unambiguous and length-prefixed, so `modbus-kit` needs nothing extra here either.

## 5. Reconnect and health

One reconnect-with-backoff policy, for both transport kinds, driven by consecutive-failure counts — never the underlying library's own `isOpen()`/`close` event, the same reasoning 07 §2 already gives for why `modbus-kit` doesn't trust `modbus-serial`'s own reconnection signal. `health()` is a synchronous, always-answerable pull; there's no push callback here — a consumer wanting to react to a state change reads it from its own scan/health loop (07a's `ScanCache`, or `DaliController.onHealth`, 12 §3) rather than this package inventing a second notification mechanism for what's already a cheap synchronous read.

## 6. Consumers

- **`modbus-kit`** (07 §3): RTU's serial port comes from here now, with the RX-flush subclass and t3.5 pacing layered on top; Modbus TCP was already framing-agnostic and gains nothing new by moving onto this package's TCP implementation, but does so anyway for one config shape across both transports.
- **`driver-dali`** (12 §4.1): `dali-foxtron-ASCII`'s own SOH/checksum/ETB framing (12 §6) is built directly on this package's byte stream, identically for `serial` and `tcp`.

## 7. Testing

Tier 1, against the simulator's own serial/TCP fixtures (`design/simulator`) — no real hardware, no real port:

- `write`/`onData` round-trip arbitrary byte sequences unchanged, for both transport kinds.
- Reconnect: a dropped connection (fixture close, or a simulated serial unplug) is retried with backoff; `health()` reports `reconnecting` throughout and `open` once it succeeds — never left at `unknown`.
- `health().consecutiveFailures` resets to 0 on a successful reconnect, and climbs on repeated failures — asserted against a fixture that fails N times before succeeding.
- Config validation: a malformed `path`/`host`/`port` is rejected at `createLineTransport`'s own construction, before `open()` is ever called.
- No framing behaviour leaks in: a consumer's own multi-write sequence arrives at the fixture's other end as the same bytes, unsegmented by this package into anything message-shaped.
