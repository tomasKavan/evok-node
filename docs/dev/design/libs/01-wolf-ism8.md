# 01 — wolf-ism8

## 1. Scope

Library `wolf-ism8`: the protocol of the Wolf ISM8i interface module (research/19). Repository `tomasKavan/wolf-ism8`, MIT, TypeScript, published as ESM and CommonJS. No runtime dependencies besides Node's own `node:net` and `node:http`. The repository is created before development starts; this file is its design until then.

```
wolf-ism8
├── codec        frames ⇄ bytes, stream reassembly, KNX datapoint types      pure, no I/O
├── datapoints   the table: ID → device, name, type, write rules, firmware
├── session      the protocol over any byte stream: ACKs, read-all, writes, liveness
├── server       node:net TCP server — the ISM8i connects to it; one session at a time
└── info         optional: firmware, hardware and serial from the ISM's web page
```

The ISM8i is a TCP **client**: it connects to one configured IP and port (default 12004) and pushes values; the library is the server (research/19 §3). HTTP is used only by `info`.

**For:** any Node application that talks to an ISM8i — evok-node's ISM8i driver (12f), a CLI, a test tool.

**Not for:**

- Wolf ISM7 / Link — another, closed protocol (research/19 §7.1).
- The KNX and BACnet sets built on the ISM8.
- Firmware updates; the ISM's web configuration.
- Plausibility filters on values — jump filters, rescaling of odd values (research/19 §4). The library decodes what the wire says; a consumer filters.

## 2. Codec

Pure functions and one stateful reader; no I/O, no clock.

```ts
type Service = 'value' | 'ack' | 'write' | 'readAll';   // sub-service F0 06 · F0 86 · F0 C1 · F0 D0

interface Item  { readonly id: number; readonly command: number; readonly raw: Uint8Array }
interface Frame { readonly service: Service; readonly start: number; readonly items: readonly Item[]; readonly bytes: Uint8Array }

class FrameReader {
  /** Feeds bytes as read from the socket; returns the frames completed by them. */
  push(chunk: Uint8Array): { frames: Frame[]; skipped: number };
}

function encodeAck(start: number): Uint8Array;              // 17 bytes; 12–13 = start (research/19 §1.2)
function encodeReadAll(): Uint8Array;                       // the 12 bytes every implementation sends (§1.3)
function encodeWrite(id: number, raw: Uint8Array): Uint8Array;
```

Byte layout: research/19 §1.1. Rules:

- **Reassembly.** `FrameReader` keeps a buffer across reads and cuts frames by the length field (bytes 4–5). A frame split over two TCP reads is joined, never dropped — the gap in wolf_ism8 and openHAB (research/19 §2).
- **Resync.** Bytes that don't start with `06 20 F0 80`, a length below 16 or above 1024, or an item running past the frame's end: the reader skips to the next `06 20 F0 80` and counts the skipped bytes. One bad frame never stops the stream.
- **Items.** Walked from offset 16 by `p += 4 + len`; an item of length 0 is returned with an empty `raw`.
- **Read-all** is sent as 12 bytes with the length field 22, as every implementation and the manual do (research/19 §1.3).

Example — a test vector, from research/19 §1.2:

```ts
const r = new FrameReader();
r.push(hex('06 20 F0 80 00 15 04 00 00 00 F0 06 01 74 00 01 01 74 03'));   // → { frames: [] }
r.push(hex('01 00'));   // → { frames: [{ service: 'value', start: 372, items: [{ id: 372, command: 3, raw: [0x00] }] }] }
encodeAck(372);         // → 06 20 F0 80 00 11 04 00 00 00 F0 86 01 74 00 00 00
```

## 3. Datapoint types

```ts
type Dpt =
  | '1.001' | '1.002' | '1.003' | '1.009'
  | '5.001' | '5.010' | '7.001'
  | '9.001' | '9.002' | '9.006' | '9.024' | '9.025'
  | '10.001' | '11.001'
  | '13.002' | '13.010' | '13.013'
  | '20.102' | '20.103' | '20.105';

type Value =
  | boolean                                                   // 1.xxx
  | number                                                    // 5.xxx, 7.001, 9.xxx, 13.xxx, 20.xxx (the code)
  | null                                                      // 9.xxx 7FFF — invalid
  | { readonly hour: number; readonly minute: number; readonly second: number; readonly weekday?: number }   // 10.001
  | { readonly year: number; readonly month: number; readonly day: number };                                 // 11.001

function decode(dpt: Dpt, raw: Uint8Array): Value;            // throws on a length that doesn't fit the type
function encode(dpt: Dpt, value: Value): Uint8Array;
```

Encodings: research/19 §4. Where implementations differ, the library does this:

| Type | Rule |
|---|---|
| 9.xxx decode | value = 0.01 · M · 2^E, M 12-bit two's complement; **only `7FFF` is invalid** (`null`) — not any mantissa `7FF` as wolf_ism8 does |
| 9.xxx encode | smallest exponent that fits, rounded — wolf_ism8's algorithm, credited in NOTICE. `encode(decode(x)) = x` for every valid 2-byte value |
| 1.009 | the raw bit, `true` = 1. Its meaning on Wolf valves is not known (research/19 §11); KNX's open/close is not applied |
| 5.001 | 0–255 ⇄ 0–100 %, rounded both ways |
| 10.001, 11.001 | weekday kept; year 2000 + `YYYYYYY` |
| 13.002 | ×0.0001 as the type says. Firmware 1.9 sometimes sends it unscaled (research/19 §4) — not corrected here |
| 20.xxx | the numeric code; names are the datapoint table's (§4) |

## 4. Datapoint table

```ts
type DeviceKind = 'boiler' | 'system' | 'directCircuit' | 'mixerCircuit' | 'mixerModule'
                | 'cascade' | 'solar' | 'ventilation' | 'heatPump';

interface DatapointDef {
  readonly id: number;
  readonly key: string;                       // stable, English: 'boiler1.flowTemperature', 'mixerCircuit2.setpointCorrection'
  readonly device: { readonly kind: DeviceKind; readonly index: number };   // index 1-based; 0 for 'system', 'directCircuit'
  readonly name: string;                      // English
  readonly nameDe: string;                    // as in Wolf's documents
  readonly dpt: Dpt;
  readonly write?: { readonly min?: number; readonly max?: number; readonly step?: number; readonly values?: readonly number[] };   // absent ⇒ read-only
  readonly enum?: Readonly<Record<number, string>>;   // 20.xxx and enumerated 5.010
  readonly since: '1.4' | '1.5' | '1.7' | '1.8' | '1.9';   // first ISM firmware with it
}

const DATAPOINTS: ReadonlyMap<number, DatapointDef>;
function datapointsOf(kind: DeviceKind, index: number): readonly DatapointDef[];
function byKey(key: string): DatapointDef | undefined;
```

- **Content** is research/19 §5: boilers 1–4, system and BM-2, the direct circuit, mixer circuits 1–3, mixer modules 1–3, and the cascade, solar, ventilation and heat-pump ranges. Built once from the per-firmware CSVs and the implementations' tables (research/19 S1, S3, S20); where they disagree, the table follows the Wolf manual (S15, S17) and says so in a comment.
- **Write rules** are the manual's: Programmwahl circuits `values: [0, 1, 2, 3]`, DHW program `[0, 2, 4]` — 1 and 3 are "keine Aktion" (research/19 §4); Sollwertkorrektur −4 … 4, step 0.5; Sparfaktor 0 … 10, step 0.5.
- **Keys** never change once published; a name may.
- **Unknown IDs** — not in the table, or from a firmware newer than it — are not an error (§5.1).
- **Bit fields** 251, 355, 356, 358 are decoded by helpers, not by the table:

  ```ts
  function presentCircuits(v251: number): { direct: boolean; mixer: number[] };   // research/19 §5.2
  function presentDevices(v355: number, v356: number): { mixerModules: number[]; boilers: number[]; solar: boolean; ventilation: boolean; bm2: boolean };
  ```

## 5. Session

The protocol over one connection. It owns no socket: it runs over any byte stream, so a test feeds it bytes and a driver may hand it a socket of its own.

```ts
interface ByteStream {
  write(bytes: Uint8Array): void;
  onData(cb: (bytes: Uint8Array) => void): void;
  onClose(cb: () => void): void;
  close(): void;
}

interface Clock {                             // evok-node passes its own (04 §4); default: Date.now and timers
  now(): number;
  setTimeout(fn: () => void, ms: number): unknown;
  clearTimeout(handle: unknown): void;
}

interface SessionOptions {
  readonly readAllAfterMs?: number;           // 60 000
  readonly keepaliveTimeoutMs?: number;       // 120 000
  readonly silenceTimeoutMs?: number;         // 3 600 000
  readonly writeMinIntervalMs?: number;       // 60 000, per datapoint
  readonly debounceMs?: Readonly<Record<number, number>>;   // { 53: 10 000 }
  readonly clock?: Clock;
}

interface ValueEvent { readonly id: number; readonly def?: DatapointDef; readonly value: Value; readonly raw: Uint8Array; readonly changed: boolean; readonly at: number }

type CloseReason = 'remote' | 'keepalive' | 'replaced' | 'closed';
type WriteResult = { ok: true } | { ok: false; reason: 'unknownId' | 'notWritable' | 'outOfRange' | 'rateLimited' | 'closed' };

class Ism8Session {
  constructor(stream: ByteStream, options?: SessionOptions);
  on(event: 'value', cb: (e: ValueEvent) => void): this;
  on(event: 'unknown', cb: (e: { id: number; raw: Uint8Array; at: number }) => void): this;   // not in the table, or not decodable
  on(event: 'stale', cb: (stale: boolean) => void): this;
  on(event: 'close', cb: (reason: CloseReason) => void): this;
  on(event: 'warning', cb: (w: { code: string; detail: string }) => void): this;
  readAll(): void;
  write(id: number, value: Value): WriteResult;
  values(): ReadonlyMap<number, { readonly value: Value; readonly at: number }>;
  readonly keepaliveSeen: boolean;
  close(): void;
}
```

### 5.1. Receiving

| Event | Session does |
|---|---|
| a complete `F0 06` frame | sends `encodeAck(start)` **first**, then decodes its items — an item that fails to decode never holds back the ACK, so the ISM never resends because of it |
| an item in the table, decoded | `value`; `changed` false when equal to the last value. A repeat of the same frame (the ISM resends) is a `value` with `changed: false` |
| an item not in the table, or failing to decode | `unknown` with its raw bytes; a `warning` once per ID |
| DP 767 | not a `value`; sets `keepaliveSeen` and restarts the keepalive timer |
| a value in `debounceMs` that changes and changes back within its time | neither change is emitted — DP 53's `01` then `00` after every reconnect (research/19 §3) |
| a frame of another service from the ISM | `warning`, no ACK |
| bytes skipped by resync (§2) | `warning` with the count |

### 5.2. Read-all and liveness

- **Read-all once.** No value within `readAllAfterMs` after the session starts ⇒ one `readAll()`. Never periodic: read-all polling made the ISM reset (research/19 §3). A consumer may call `readAll()` itself — after a write it can't confirm, say.
- **Keepalive.** Once DP 767 has been seen, no 767 for `keepaliveTimeoutMs` ⇒ `close('keepalive')`. The ISM connects again and the server takes the new session (§6).
- **Silence.** Without 767 (firmware before 1.9), nothing for `silenceTimeoutMs` ⇒ `stale(true)`, and `stale(false)` on the next frame. The session stays open: night traffic is sparse, and closing a working connection would cost a reconnect.

### 5.3. Writing

1. The ID must be in the table and writable, the value inside `write`'s range, on its step, or in its values; otherwise the matching `reason`, nothing sent.
2. Not more often than `writeMinIntervalMs` per datapoint ⇒ `rateLimited`. The BM-2 stores parameters in EEPROM and no safe rate is known (research/19 §6).
3. Encoded and sent as one `F0 C1` frame.
4. The session's value does **not** change. It changes when the ISM reports the new value — what the module holds, not what was asked for. No reply to a write is known (research/19 §1.4); a consumer that needs a confirmation waits for the `value` and calls `readAll()` if none comes.

## 6. Server

The transport used by evok-node: a TCP server the ISM8i connects to.

```ts
interface ServerOptions extends SessionOptions {
  readonly port?: number;                     // 12004
  readonly host?: string;                     // default: all interfaces
  readonly allow?: readonly string[];         // source IPs; absent ⇒ any
}

class Ism8Server {
  constructor(options?: ServerOptions);
  on(event: 'session', cb: (s: Ism8Session, peer: { address: string; port: number }) => void): this;
  on(event: 'sessionEnd', cb: (reason: CloseReason) => void): this;
  on(event: 'rejected', cb: (peer: { address: string }) => void): this;
  on(event: 'error', cb: (e: Error) => void): this;   // listen failures only
  listen(): Promise<void>;
  close(): Promise<void>;
  readonly session: Ism8Session | undefined;
}
```

- **One session.** The ISM has one target and opens one connection (research/19 §3). A new allowed connection closes the old session (`replaced`) and becomes the session — after a power cycle the old socket may still look open.
- A connection from outside `allow` is closed at once, `rejected`.
- Sockets: `setNoDelay(true)`, TCP keepalive on.
- `close()` ends the session (`closed`) and stops listening.

```ts
const server = new Ism8Server({ port: 12004, allow: ['192.168.10.40'] });
server.on('session', (s) => {
  s.on('value', (e) => { if (e.changed) console.log(e.def?.key, e.value); });
});
await server.listen();
// later
server.session?.write(byKey('mixerCircuit1.setpointCorrection')!.id, 1.5);
```

## 7. Info

```ts
function fetchInfo(host: string, options?: { timeoutMs?: number }): Promise<{ firmware?: string; hardware?: string; serial?: string }>;
```

`GET http://<host>/`, read with the expressions the Home Assistant integration uses — `FW-Version.*?(\d+\.\d+)`, `HW-Version.*?(\d+\.\d+)` (research/19 §8). No datapoint carries the firmware. A field not found is absent; an unreachable host rejects. Optional: nothing else in the library needs it.

## 8. Errors

- The data path never throws: a bad frame, item or value becomes a `warning` or `unknown`.
- `decode` and `encode` throw on a wrong length or a value outside the type; `Session.write` checks first and answers a `WriteResult`.
- No logging of its own. Every warning has a stable `code`: `resync`, `unknownId`, `decodeFailed`, `unexpectedService`.

## 9. Testing

- **Vectors.** Every frame in research/19 §1 is a test: parse, ACK, write encodings.
- **Reassembly.** Each vector split at every byte offset; two frames in one chunk; garbage before, between and inside frames.
- **DPT 9.** Encode ∘ decode over all 65 536 values; the encoders' known failures from research/19 §4 (81.88, −0.01, negatives) as cases.
- **Session** with a fake `ByteStream` and fake `Clock`: ACK before decode; resends as `changed: false`; read-all once and only without data; keepalive close; silence `stale`; DP 53 debounce; every `WriteResult`; no value change on write.
- **Server** on loopback: replace, reject, close.
- No hardware needed. A recorded session from the house's ISM, once available, becomes a fixture.

## 10. Repository

- Created by Tomas before development; this design moves to its README then.
- TypeScript, ESM and CommonJS builds, Vitest, ESLint — as evok-node, so the same tools work in both.
- `NOTICE`: the DPT 9 encoder after wolf_ism8 (MIT, research/19 §9). No code from openHAB (EPL-2.0) or FHEM (no licence).

## 11. Open

- **The ISM's answer to a write**, and whether a written value survives a power cycle (research/19 §1.4, §6). The session doesn't rely on either.
- **A safe write rate.** 60 s per datapoint is a guess; the question is with Wolf CZ.
- **Read-all's length field** (12 bytes sent, 22 declared). Sent as everyone does; untested whether it eats the next bytes.
- **The web page's login**, if `info` needs one.
- **Firmware before 1.9** — no keepalive; the silence timeout is the only liveness check.
