# 07 — Modbus driver

## 1. Scope

The shared ancestor of the onboard and extension drivers (08, 09): everything Modbus, nothing Unipi-model-specific. Transport, framing, correlation, timing, batching and breakers live here; a hardware definition — what a register means, which model has which sections, how multi-register values group — never does. That split is what stops 08 and 09 from drifting into two independent implementations of the same wire protocol.

Two ways this file gets used. Standalone, configured directly (`type: modbus-kit`), it's a real driver: it owns one transport and exposes it raw, function-code by function-code, for a device or a third-party plugin that speaks Modbus directly — 01 §7's shared-resource pattern, and the only place this file's own endpoints get bound. Embedded, it's not a driver at all — just the engine, constructed and held directly by whatever driver owns the transport, which builds its own typed endpoints on top and never exposes a raw endpoint unless it chooses to (§7).

This package also hosts `hw-modbus-kit` (07a) — the binder that turns a `hw-definitions`-resolved definition into bound `driver-kit` devices, for `driver-onboard` and `driver-extension` alike. It's a distinct concern from everything else in this file, kept in its own `src/hw-modbus-kit/` subpath rather than blended in: this file stays "everything Modbus, nothing hardware-specific," 07a is "everything hardware-specific, on top of this file's own transport."

## 2. Modbus library: wrap, don't reinvent

`modbus-serial`, behind this file's own `ModbusTransport` — never used raw, and never reimplemented from scratch. No current JS library has the one bug that would justify writing a framer from nothing (pymodbus's transaction-id correlation overflow), and Modbus's own framing looks simpler than it is: two of the largest JS industrial consumers (`node-red-contrib-modbus`, an ioBroker adapter) each got burned by the same shared libraries and ended up forking or rewriting rather than patching around it. `modbus-serial` is the still-maintained option with the best post-match validation (unit id, function code, length and CRC, all checked after a match), and it already sits on `serialport`, so RTU's own serial-port handling is inherited, not a separate decision (§3).

What it doesn't do safely, and what this file's own wrapper supplies:

- A per-line async mutex — one per physical bus, never per slave or per caller; the library has no queue of its own, and its internal state is single mutable slots a second overlapping request destroys.
- RX flush before every request, via a subclassed port. Without it, a response that arrives late for a request that already timed out gets silently returned as the *next* request's answer — valid CRC, matching unit id, matching function code, wrong data.
- A strict unit-id, function-code and CRC gate on every match, before any byte is consumed from the buffer.
- t3.5 inter-transaction pacing on RTU, derived from baud rate — no maintained library implements this.
- An outer deadline via the same `Deadline`/`AbortSignal` machinery every other call in this codebase uses (04 §6) — the library's own cancellation clears timers without rejecting, which would otherwise leave a promise permanently unsettled.
- A reconnect supervisor driven by consecutive-failure counts, never the library's own `isOpen()` or `close` event.
- Retry-with-backoff, idempotent reads only — a write is never blind-retried.
- A cap on outstanding TCP requests, since the transaction-id table has a fixed number of slots and silently overwrites past it.

TCP needs almost none of this on top: MBAP framing is length-prefixed and unambiguous, and the library's own handling of it is correct.

## 3. Serial ports are not a separate decision

RTU's serial-port handling comes from `serialport`, underneath `modbus-serial`'s own port abstraction — this file never opens a serial port itself. The one thing it does add is a subclass of that port, for the RX-flush behaviour §2 already requires; nothing else about serial I/O is this file's to reimplement.

## 4. The engine

One class, `ModbusTransport`, constructed by `createModbusTransport` — never subclassed, never a `ModuleInstance` itself. Whatever owns it — the standalone driver in §6, or an embedding driver per §7 — is responsible for calling `open()` in its own `configure()` and `close()` in its own `stop()`; the engine has no lifecycle of its own beyond that.

```ts
// @evok-node/modbus-kit

interface ModbusRequestBase {
  unitId: number;         // TCP: MBAP unit id; RTU: slave address
  address: number;        // 0-based, per Modbus PDU addressing
  deadline?: Deadline;    // 04 §6; omitted ⇒ this transport's own default timeout
}

interface ModbusHealth {
  state: 'unknown' | 'probing' | 'online' | 'degraded' | 'offline';
  consecutiveFailures: number;
  lastSuccessAt: Millis | null;
}

type ModbusTransportConfig =
  | { kind: 'modbus-tcp'; host: string; port: number; timeoutMs?: number }
  | { kind: 'modbus-rtu'; path: string; baudRate: number;
      dataBits?: 7 | 8; stopBits?: 1 | 2; parity?: 'none' | 'even' | 'odd'; timeoutMs?: number };
      // t3.5 pacing is derived from baudRate, never a separate config key

interface ModbusTransport {
  open(): Promise<void>;
  close(): Promise<void>;

  readCoils(req: ModbusRequestBase & { count: number }): Promise<CallOutcome<boolean[], ModbusExceptionKind>>;             // FC1
  readDiscreteInputs(req: ModbusRequestBase & { count: number }): Promise<CallOutcome<boolean[], ModbusExceptionKind>>;    // FC2
  readHoldingRegisters(req: ModbusRequestBase & { count: number }): Promise<CallOutcome<number[], ModbusExceptionKind>>;   // FC3
  readInputRegisters(req: ModbusRequestBase & { count: number }): Promise<CallOutcome<number[], ModbusExceptionKind>>;     // FC4

  writeSingleCoil(req: ModbusRequestBase & { value: boolean }): Promise<CallOutcome<boolean, ModbusExceptionKind>>;        // FC5
  writeSingleRegister(req: ModbusRequestBase & { value: number }): Promise<CallOutcome<number, ModbusExceptionKind>>;      // FC6
  writeMultipleCoils(req: ModbusRequestBase & { values: boolean[] }): Promise<CallOutcome<void, ModbusExceptionKind>>;     // FC15
  writeMultipleRegisters(req: ModbusRequestBase & { values: number[] }): Promise<CallOutcome<void, ModbusExceptionKind>>;  // FC16

  health(unitId?: number): ModbusHealth;   // whole line if omitted, one slave's breaker state if given
}

function createModbusTransport(config: ModbusTransportConfig, deps: { clock: Clock; log: Logger }): ModbusTransport;
```

Every register is a `number` — a 16-bit unsigned value, exactly what Modbus itself defines it as — and every coil a `boolean`, never a `Buffer`. What a register's bytes *mean* — signed or not, which two registers form a wider value, word order — is never decided here; that's a hardware definition's job (08, 09), and this file stops exactly at the wire's own unit of transfer.

`deps` is `{ clock, log }`, not the whole `InstanceContext` (03 §9) — the engine has no legitimate use for `messaging` or `reportFatal`. `clock` is load-bearing: every default timeout, `lastSuccessAt`, and t3.5's own pacing read it, and it has to be the same clock the rest of the owning instance uses, so a `FakeClock` swap in a test reaches this file too (04 §4).

`writeSingleCoil`/`writeSingleRegister` return the value the slave actually echoed — FC5/FC6's own response carries it. `writeMultipleCoils`/`writeMultipleRegisters` return nothing on success — FC15/FC16's response is only an address-and-count echo of what the caller already sent, so there's genuinely nothing new to hand back; `CallOutcome<void, ...>` says that honestly rather than repeating the caller's own input.

## 5. Domain errors: Modbus exceptions

A slave exception response — the device answered, and refused — is the one Modbus failure that doesn't fit `03 §7`'s generic `ErrorKind`s: it's neither `unreachable` (the device answered fine) nor `bad-payload` (the shape was valid; this is the device's own semantic rejection). It's exactly what `domain-error` (03 §7) exists for, and every method here declares the same closed set:

```ts
type ModbusExceptionKind =
  | 'illegal-function' | 'illegal-data-address' | 'illegal-data-value'
  | 'slave-device-failure' | 'acknowledge' | 'slave-device-busy'
  | 'negative-acknowledge' | 'memory-parity-error'
  | 'gateway-path-unavailable' | 'gateway-target-device-failed-to-respond'
  | 'unknown-exception';   // a non-standard code some slave returns — info.code still carries it

const MODBUS_EXCEPTION_KINDS: readonly ModbusExceptionKind[] = [
  'illegal-function', 'illegal-data-address', 'illegal-data-value', 'slave-device-failure',
  'acknowledge', 'slave-device-busy', 'negative-acknowledge', 'memory-parity-error',
  'gateway-path-unavailable', 'gateway-target-device-failed-to-respond', 'unknown-exception',
];
```

These are the standard Modbus exception codes (1–8, 10, 11), named rather than left as bare numbers, with `unknown-exception` as the fallback for a vendor-specific code outside that set — `info: { code: number }` on the `CallOutcome` carries the raw value either way, so nothing is lost even in the fallback case. `notConnected`, `io`, `framing` and an open breaker all surface as the generic `unreachable`; a timeout surfaces as the generic `timeout` — both directly returnable from a handler per `05a §6.4`, needing no domain vocabulary of their own.

## 6. The raw endpoints

Bound only by the standalone driver below — an embedding driver (§7) calls the engine's own typed methods directly and has no reason to touch these unless it's deliberately re-exposing them itself.

```ts
interface ModbusReadArgs { unitId: number; address: number; count: number }
interface ModbusWriteSingleCoilArgs { unitId: number; address: number; value: boolean }
interface ModbusWriteSingleRegisterArgs { unitId: number; address: number; value: number }
interface ModbusWriteMultipleCoilsArgs { unitId: number; address: number; values: boolean[] }
interface ModbusWriteMultipleRegistersArgs { unitId: number; address: number; values: number[] }
// no `deadline` field on any of these — already on the envelope (03 §2), read via `req.deadline`

const ModbusReadArgsCodec              = Codecs.struct({ unitId: Codecs.uint16, address: Codecs.uint16, count: Codecs.uint16 });
const ModbusSingleCoilArgsCodec        = Codecs.struct({ unitId: Codecs.uint16, address: Codecs.uint16, value: Codecs.bool });
const ModbusSingleRegisterArgsCodec    = Codecs.struct({ unitId: Codecs.uint16, address: Codecs.uint16, value: Codecs.uint16 });
const ModbusMultipleCoilsArgsCodec     = Codecs.struct({ unitId: Codecs.uint16, address: Codecs.uint16, values: Codecs.array(Codecs.bool) });
const ModbusMultipleRegistersArgsCodec = Codecs.struct({ unitId: Codecs.uint16, address: Codecs.uint16, values: Codecs.array(Codecs.uint16) });

export const READ_COILS             = method('readCoils', 'none', Codecs.array(Codecs.bool), ModbusReadArgsCodec, { errorKinds: MODBUS_EXCEPTION_KINDS });
export const READ_DISCRETE_INPUTS   = method('readDiscreteInputs', 'none', Codecs.array(Codecs.bool), ModbusReadArgsCodec, { errorKinds: MODBUS_EXCEPTION_KINDS });
export const READ_HOLDING_REGISTERS = method('readHoldingRegisters', 'none', Codecs.array(Codecs.uint16), ModbusReadArgsCodec, { errorKinds: MODBUS_EXCEPTION_KINDS });
export const READ_INPUT_REGISTERS   = method('readInputRegisters', 'none', Codecs.array(Codecs.uint16), ModbusReadArgsCodec, { errorKinds: MODBUS_EXCEPTION_KINDS });

export const WRITE_SINGLE_COIL        = method('writeSingleCoil', 'mutates', Codecs.bool, ModbusSingleCoilArgsCodec, { errorKinds: MODBUS_EXCEPTION_KINDS });
export const WRITE_SINGLE_REGISTER    = method('writeSingleRegister', 'mutates', Codecs.uint16, ModbusSingleRegisterArgsCodec, { errorKinds: MODBUS_EXCEPTION_KINDS });
export const WRITE_MULTIPLE_COILS     = method('writeMultipleCoils', 'mutates', Codecs.void, ModbusMultipleCoilsArgsCodec, { errorKinds: MODBUS_EXCEPTION_KINDS });
export const WRITE_MULTIPLE_REGISTERS = method('writeMultipleRegisters', 'mutates', Codecs.void, ModbusMultipleRegistersArgsCodec, { errorKinds: MODBUS_EXCEPTION_KINDS });

const ModbusHealthArgsCodec = Codecs.struct({ unitId: Codecs.uint16() });   // omitted ⇒ whole-line health, same as ModbusTransport.health() itself
export const HEALTH = method('health', 'none', ModbusHealthCodec, ModbusHealthArgsCodec);   // not a function code — see below

// One Device, nine sibling fields, no '@' — there's no single "primary" operation to root the tail on,
// and binding is mandatory through a Device regardless (05a §6.3), even for a bundle with no root field.
export const MODBUS_RAW = device('modbus-kit.raw', {
  readCoils: READ_COILS, readDiscreteInputs: READ_DISCRETE_INPUTS,
  readHoldingRegisters: READ_HOLDING_REGISTERS, readInputRegisters: READ_INPUT_REGISTERS,
  writeSingleCoil: WRITE_SINGLE_COIL, writeSingleRegister: WRITE_SINGLE_REGISTER,
  writeMultipleCoils: WRITE_MULTIPLE_COILS, writeMultipleRegisters: WRITE_MULTIPLE_REGISTERS,
  health: HEALTH,
});
```

Eight methods, one per function code, deliberately not collapsed into a query/command pair discriminated by an `op` field. Four are forced apart — coils, discrete inputs, holding and input registers are different address spaces with different access rights on the slave, not a style choice. The other four could have collapsed (`writeSingleCoil` into `writeMultipleCoils` with `count: 1`, and the register equivalent), but a raw driver's whole purpose is letting the caller pick the exact wire operation rather than have the transport guess — concretely relevant here, since it's still unverified whether Unipi's own atomic write semantics (`research/05` §7.4) are tied to the multi-register function code specifically, even for what looks like a single value.

`health` is the ninth field and not a function code at all — it's the one way a caller relaying through this device (§7) learns the owning line's breaker state without a local `ModbusTransport` object of its own to call `health()` on directly. `onCall` for it is a pure forward to `t.health(a?.unitId)`, always `{ok: true, ...}`, since a local, synchronous state read never fails the way a wire call can.

```ts
interface ModbusDriverConfig {
  transport: ModbusTransportConfig;
}

class ModbusDriver implements ModuleInstance<ModbusDriverConfig> {
  private kit: DriverKit;
  private transport?: ModbusTransport;

  constructor(private ctx: InstanceContext) { this.kit = createDriverKit(ctx); }

  async configure(config: ModbusDriverConfig): Promise<void> {
    this.transport = createModbusTransport(config.transport, { clock: this.ctx.clock, log: this.ctx.log });
    await this.transport.open();
  }

  async start(): Promise<void> {
    const t = this.transport!;
    this.kit.bindDevice('raw', MODBUS_RAW, {
      readCoils:              { onCall: (a, req) => t.readCoils({ ...a, deadline: req.deadline }) },
      readDiscreteInputs:     { onCall: (a, req) => t.readDiscreteInputs({ ...a, deadline: req.deadline }) },
      readHoldingRegisters:   { onCall: (a, req) => t.readHoldingRegisters({ ...a, deadline: req.deadline }) },
      readInputRegisters:     { onCall: (a, req) => t.readInputRegisters({ ...a, deadline: req.deadline }) },
      writeSingleCoil:        { onCall: (a, req) => t.writeSingleCoil({ ...a, deadline: req.deadline }) },
      writeSingleRegister:    { onCall: (a, req) => t.writeSingleRegister({ ...a, deadline: req.deadline }) },
      writeMultipleCoils:     { onCall: (a, req) => t.writeMultipleCoils({ ...a, deadline: req.deadline }) },
      writeMultipleRegisters: { onCall: (a, req) => t.writeMultipleRegisters({ ...a, deadline: req.deadline }) },
      health:                 { onCall: (a) => ({ ok: true, result: t.health(a?.unitId) }) },
    });
    this.kit.attach();
  }

  async drain(): Promise<void> {}   // no scan loop of its own — nothing to drain
  async stop(): Promise<void> { await this.transport?.close(); }
}

const modbusDriverDescriptor: ModuleDescriptor<ModbusDriverConfig> = {
  schema: ModbusDriverConfigSchema,
  isConfigEqual: (a, b) => deepEqual(a.transport, b.transport),
  createInstance: (ctx) => new ModbusDriver(ctx),
};
```

Every `onCall` is a pure forward, nothing translated in between — the engine and the endpoint speak the same `CallOutcome` shape (05a §6.4), so there is no separate mapping layer for this file to get wrong.

## 7. Composing, not subclassing

A driver that owns a Modbus transport outright never subclasses anything from this file — it embeds the engine. It calls `createModbusTransport` once, from its own `configure()`, holds the result, calls the typed methods directly to implement whatever endpoints its own hardware definition calls for, and calls `close()` from its own `stop()`. It never touches `ModbusDriver` or the nine endpoint constants above, and its own callers never see a raw Modbus address at all — only whatever typed endpoints it chose to expose.

The one reason it would reach for those constants anyway: if it owns a line another driver needs to share (01 §7), it `bindDevice`s the same `MODBUS_RAW` itself, on its own tail, so the dependent can speak raw Modbus to a device this file's own author never anticipated — the onboard and extension drivers are the current example, each owning one line or socket outright and free to make that call independently.

There are, correspondingly, two ways to obtain a `ModbusTransport` at all — both produce the identical interface, so nothing above this line, including 07a's `hw-modbus-kit`, ever needs to know which one it got:

```ts
// @evok-node/modbus
function createModbusTransport(config: ModbusTransportConfig, deps: { clock: Clock; log: Logger }): ModbusTransport;      // §4 — owns the line outright
function createRelayModbusTransport(ctx: InstanceContext, remoteTail: Tail): ModbusTransport;                             // relays through another instance's MODBUS_RAW
```
`createRelayModbusTransport` needs `ctx.messaging`, not `{clock, log}` — it's forwarding `CALL`s to `remoteTail`'s own `MODBUS_RAW` device rather than touching a wire, and that forwarding is trivial precisely because `MODBUS_RAW`'s bound methods (§6) share the exact same `CallOutcome` shape `ModbusTransport`'s own methods return: no translation layer, every method a 1:1 forward. `health()` relays the same way, through `MODBUS_RAW`'s ninth field (§6) — the one method on this device that isn't a function code, added for exactly this case, since a relay has no local breaker state of its own to read.

## 8. Placement: native code and process isolation

RTU's dependency on `serialport` means a `modbus-kit`-based driver on that transport is running native code, in the sense `01 §8` already flags: a crash inside that native binding takes down whichever OS process it's running in, `worker_thread` or `child_process` alike, regardless of which thread triggered it — `worker_thread`'s own isolation guarantee doesn't extend to a native-code fault. Under `child_process`, that fault takes only that one instance's process down; under `worker_thread`, it takes `main` and every other instance sharing that process down with it.

How likely that is in practice is a separate question from whether it's possible, and worth being honest about: `serialport`'s native layer is mature and widely deployed, not the kind of dependency that crashes routinely — this isn't a reason to expect trouble, only a reason the two placements aren't equivalent if it does happen. Whether that residual risk is worth `child_process`'s extra overhead for a given RTU line, versus accepting it for `worker_thread`'s lower cost, is the config author's own call (`01 §3`'s `run:` key) — this file states the consequence, not the answer. Modbus TCP carries no native dependency at all, so this consideration doesn't apply to a pure-TCP driver.

## 9. Testing

Tier 1, `packages/modbus-kit`, against the simulator (`design/simulator`) — no hardware, no real serial port:

- Stale-frame flush: a response arriving after its own request already timed out must never be returned as the next request's answer.
- t3.5 pacing: consecutive RTU transactions are never closer together than the baud-derived minimum gap.
- The per-line mutex: two overlapping calls against the same transport are never in flight on the wire at once, regardless of call order.
- Deadline behaviour: a call whose deadline elapses resolves `{ok:false, kind:'timeout', ...}`, never hangs, never leaves a promise unsettled.
- Retry: an idempotent read is retried per the wrapper's own backoff; none of the four write methods is ever retried automatically, even on a transport-level failure.
- The TCP transaction-id cap: outstanding requests never exceed the table's own slot count.
- Exception mapping: each of the standard exception codes surfaces as its matching `ModbusExceptionKind`, and an unrecognised code surfaces as `unknown-exception` with `info.code` carrying the raw value, never `internal-error`.
- Per-unit breaker isolation: one unit answering nothing must not affect calls addressed to a different unit on the same line.
