#!/usr/bin/env python3
"""Capture stock EVOK 3.0.6 event transcripts: WebSocket sessions and webhook deliveries.

Runs from the laptop, over the network. Stdlib only — no pip, no venv, nothing installed
on the unit. Python 3.9+.

The three WebSocket cases are separate fixtures because their payload *shapes* differ, and
that difference is the compatibility contract:

  default   default filter — Modbus changes arrive as an array, 1-Wire as a bare object
  filtered  {"cmd":"filter","devices":[...]} — always an array, non-matching suppressed
  all       {"cmd":"all"} — one array of every device's full()

Usage
  # 1. WebSocket, default filter, 5 minutes, direct to :8080
  ./capture-events.py ws --host 10.0.0.11 --minutes 5 --label default

  # 2. WebSocket, type filter
  ./capture-events.py ws --host 10.0.0.11 --minutes 5 --label filtered \
      --filter di,ro,do,ai,ao

  # 3. WebSocket cmd:all snapshot, then exit
  ./capture-events.py ws --host 10.0.0.11 --cmd-all --label all --minutes 1

  # 4. Same but through nginx on :80 (the only path some real clients have)
  ./capture-events.py ws --host 10.0.0.11 --port 80 --label default-nginx --minutes 5

  # 5. Webhook receiver on the laptop; point EVOK's apis.webhook.address here
  ./capture-events.py webhook --bind 0.0.0.0 --port 9099 --minutes 10

While a WebSocket capture runs, make inputs change: toggle a DI by hand, warm a DS18B20,
and — on the L527 — close a relay wired to a DI on another section. A transcript with no
events in it is not a fixture.

Every line of output is one JSON object: {"t": <monotonic ms>, "dir": "rx"|"tx", ...}.
Nothing is reformatted; raw frame payloads are preserved verbatim as strings.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import socket
import struct
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

# --------------------------------------------------------------------------- output


class Sink:
    """Append-only JSONL writer with a monotonic clock relative to session start."""

    def __init__(self, path: str) -> None:
        self.path = path
        self.fh = open(path, "a", buffering=1, encoding="utf-8")
        self.t0 = time.monotonic()

    def write(self, **rec: object) -> None:
        rec["t"] = round((time.monotonic() - self.t0) * 1000, 3)
        self.fh.write(json.dumps(rec, ensure_ascii=False, sort_keys=True) + "\n")

    def close(self) -> None:
        self.fh.close()


def outpath(args: argparse.Namespace, kind: str) -> str:
    os.makedirs(args.outdir, exist_ok=True)
    stamp = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
    unit = getattr(args, "unit", None) or getattr(args, "host", "local")
    label = getattr(args, "label", None) or kind
    return os.path.join(args.outdir, f"{kind}-{unit}-{label}-{stamp}.jsonl")


# ------------------------------------------------------------------- websocket client
# Minimal RFC 6455 client. Enough for EVOK: text frames, no extensions, no subprotocol,
# no compression. EVOK sends no ping and expects no pong, but we answer pings anyway.

OPCODE = {0x0: "cont", 0x1: "text", 0x2: "binary", 0x8: "close", 0x9: "ping", 0xA: "pong"}


class WSError(RuntimeError):
    pass


class WSClient:
    def __init__(self, host: str, port: int, path: str = "/ws", timeout: float = 10.0):
        self.sock = socket.create_connection((host, port), timeout=timeout)
        self.buf = b""
        self._handshake(host, port, path)

    def _handshake(self, host: str, port: int, path: str) -> None:
        key = base64.b64encode(os.urandom(16)).decode()
        req = (
            f"GET {path} HTTP/1.1\r\n"
            f"Host: {host}:{port}\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            f"Sec-WebSocket-Key: {key}\r\n"
            "Sec-WebSocket-Version: 13\r\n"
            # EVOK's check_origin returns True unconditionally; send one anyway so the
            # transcript shows what a browser-like client looks like on the wire.
            f"Origin: http://{host}\r\n"
            "\r\n"
        )
        self.sock.sendall(req.encode())
        while b"\r\n\r\n" not in self.buf:
            chunk = self.sock.recv(4096)
            if not chunk:
                raise WSError("connection closed during handshake")
            self.buf += chunk
        head, _, self.buf = self.buf.partition(b"\r\n\r\n")
        self.response_headers = head.decode("latin-1")
        status = self.response_headers.split("\r\n", 1)[0]
        if not re.match(r"HTTP/1\.[01] 101", status):
            raise WSError(f"upgrade refused: {status}\n{self.response_headers}")

    def _recv_exact(self, n: int) -> bytes:
        while len(self.buf) < n:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise WSError("connection closed")
            self.buf += chunk
        out, self.buf = self.buf[:n], self.buf[n:]
        return out

    def recv_frame(self) -> tuple[str, bytes]:
        b0, b1 = self._recv_exact(2)
        opcode = OPCODE.get(b0 & 0x0F, f"unknown-{b0 & 0x0F:x}")
        fin = bool(b0 & 0x80)
        length = b1 & 0x7F
        if length == 126:
            (length,) = struct.unpack("!H", self._recv_exact(2))
        elif length == 127:
            (length,) = struct.unpack("!Q", self._recv_exact(8))
        if b1 & 0x80:  # server must not mask, but handle it rather than desync
            mask = self._recv_exact(4)
            data = bytes(b ^ mask[i % 4] for i, b in enumerate(self._recv_exact(length)))
        else:
            data = self._recv_exact(length)
        if not fin:
            # Tornado does not fragment these payloads in practice, but nothing in the
            # research rules it out, and a partial frame must not be silently truncated.
            more_op, more = self.recv_frame()
            data += more
        return opcode, data

    def send_text(self, text: str) -> None:
        payload = text.encode()
        mask = os.urandom(4)
        masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        n = len(payload)
        if n < 126:
            header = struct.pack("!BB", 0x81, 0x80 | n)
        elif n < 1 << 16:
            header = struct.pack("!BBH", 0x81, 0x80 | 126, n)
        else:
            header = struct.pack("!BBQ", 0x81, 0x80 | 127, n)
        self.sock.sendall(header + mask + masked)

    def send_pong(self, data: bytes) -> None:
        mask = os.urandom(4)
        masked = bytes(b ^ mask[i % 4] for i, b in enumerate(data))
        self.sock.sendall(struct.pack("!BB", 0x8A, 0x80 | len(data)) + mask + masked)

    def close(self) -> None:
        try:
            self.sock.sendall(struct.pack("!BB", 0x88, 0x80) + os.urandom(4))
        except OSError:
            pass
        self.sock.close()


def run_ws(args: argparse.Namespace) -> int:
    path = args.path
    sink = Sink(outpath(args, "ws"))
    print(f"→ {sink.path}")
    ws = WSClient(args.host, args.port, path, timeout=args.timeout)
    sink.write(dir="meta", event="open", host=args.host, port=args.port, path=path,
               headers=ws.response_headers)
    print(f"connected ws://{args.host}:{args.port}{path}")

    if args.filter:
        msg = json.dumps({"cmd": "filter",
                          "devices": [d.strip() for d in args.filter.split(",")]})
        ws.send_text(msg)
        sink.write(dir="tx", frame=msg)
        print(f"tx {msg}   (no response is expected — filter is silent)")
    if args.cmd_all:
        msg = json.dumps({"cmd": "all"})
        ws.send_text(msg)
        sink.write(dir="tx", frame=msg)
        print(f"tx {msg}")

    deadline = time.monotonic() + args.minutes * 60
    ws.sock.settimeout(2.0)
    count = 0
    try:
        while time.monotonic() < deadline:
            try:
                opcode, data = ws.recv_frame()
            except socket.timeout:
                continue
            except WSError as e:
                sink.write(dir="meta", event="closed", reason=str(e))
                print(f"connection closed: {e}")
                break
            if opcode == "ping":
                ws.send_pong(data)
                sink.write(dir="meta", event="ping")
                continue
            if opcode == "close":
                sink.write(dir="meta", event="server-close", payload=data.hex())
                print("server closed the connection")
                break
            text = data.decode("utf-8", "replace")
            rec: dict[str, object] = {"dir": "rx", "opcode": opcode, "frame": text}
            try:
                parsed = json.loads(text)
                # The shape is the point: array for Modbus, bare object for 1-Wire.
                rec["shape"] = "array" if isinstance(parsed, list) else type(parsed).__name__
                if isinstance(parsed, list):
                    rec["n"] = len(parsed)
            except json.JSONDecodeError:
                rec["shape"] = "not-json"
            sink.write(**rec)
            count += 1
            left = int(deadline - time.monotonic())
            print(f"\rrx {count} frames   {left:4d}s left   last shape="
                  f"{rec.get('shape')}    ", end="", flush=True)
    except KeyboardInterrupt:
        print("\ninterrupted")
    finally:
        ws.close()
        sink.write(dir="meta", event="done", frames=count)
        sink.close()
    print(f"\n{count} frames captured → {sink.path}")
    if count == 0:
        print("WARNING: zero frames. Make an input change and record again — an empty\n"
              "         transcript is not a fixture.")
        return 1
    return 0


# ----------------------------------------------------------------- webhook receiver


def run_webhook(args: argparse.Namespace) -> int:
    sink = Sink(outpath(args, "webhook"))
    print(f"→ {sink.path}")

    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def _record(self, method: str) -> None:
            n = int(self.headers.get("Content-Length") or 0)
            body = self.rfile.read(n).decode("utf-8", "replace") if n else ""
            rec: dict[str, object] = {
                "dir": "rx",
                "method": method,
                "path": self.path,
                "headers": dict(self.headers.items()),
                "body": body,
            }
            if body:
                try:
                    parsed = json.loads(body)
                    rec["shape"] = ("array" if isinstance(parsed, list)
                                    else type(parsed).__name__)
                except json.JSONDecodeError:
                    rec["shape"] = "not-json"
            else:
                # complex_events: false → bare GET ping, Content-Type set, no body.
                rec["shape"] = "empty"
            sink.write(**rec)
            self.send_response(200)
            self.send_header("Content-Length", "2")
            self.end_headers()
            self.wfile.write(b"ok")
            print(f"{method} {self.path} shape={rec['shape']} len={len(body)}")

        def do_GET(self) -> None:      # noqa: N802
            self._record("GET")

        def do_POST(self) -> None:     # noqa: N802
            self._record("POST")

        def log_message(self, *a: object) -> None:
            pass

    srv = ThreadingHTTPServer((args.bind, args.port), Handler)
    srv.timeout = 1.0
    print(f"listening on http://{args.bind}:{args.port}/  for {args.minutes} min")
    print("set apis.webhook.address on the unit to point here, then restart evok")
    deadline = time.monotonic() + args.minutes * 60
    try:
        while time.monotonic() < deadline:
            srv.handle_request()
    except KeyboardInterrupt:
        print("\ninterrupted")
    finally:
        srv.server_close()
        sink.write(dir="meta", event="done")
        sink.close()
    print(f"→ {sink.path}")
    return 0


# ------------------------------------------------------------------------------ cli


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--outdir", default="./capture-events",
                   help="where the .jsonl transcripts go (default ./capture-events)")
    sub = p.add_subparsers(dest="mode", required=True)

    w = sub.add_parser("ws", help="capture a WebSocket session")
    w.add_argument("--host", required=True)
    w.add_argument("--port", type=int, default=8080,
                   help="8080 direct, 80 through nginx (default 8080)")
    w.add_argument("--path", default="/ws")
    w.add_argument("--unit", help="unit name for the filename, e.g. l527")
    w.add_argument("--label", help="fixture label, e.g. default / filtered / all")
    w.add_argument("--filter", help="comma-separated device types for {cmd:filter}")
    w.add_argument("--cmd-all", action="store_true", help="send {cmd:all} on connect")
    w.add_argument("--minutes", type=float, default=5.0)
    w.add_argument("--timeout", type=float, default=10.0)
    w.set_defaults(func=run_ws)

    h = sub.add_parser("webhook", help="run a webhook receiver")
    h.add_argument("--bind", default="0.0.0.0")
    h.add_argument("--port", type=int, default=9099)
    h.add_argument("--unit", help="unit name for the filename")
    h.add_argument("--label", help="fixture label, e.g. complex / simple")
    h.add_argument("--minutes", type=float, default=10.0)
    h.set_defaults(func=run_webhook)

    args = p.parse_args()
    try:
        return int(args.func(args))
    except WSError as e:
        print(f"websocket error: {e}", file=sys.stderr)
        return 2
    except OSError as e:
        print(f"network error: {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
