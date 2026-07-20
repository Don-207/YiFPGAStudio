#!/usr/bin/env python3
"""Resident YiFPGA JTAG mailbox-to-local-TCP bridge."""

from __future__ import annotations

import argparse
import asyncio
import base64
from dataclasses import asdict, dataclass
import hashlib
import json
from pathlib import Path
import signal
import sys
import time

from bridge_protocol import TYPE_SESSION, TYPE_STATUS, data_frame, hello, json_frame
from jtag_backend import JtagBackend, MockBackend, TargetIdentity, TargetSelectionError
from mailbox_model import DEFAULT_MAX_BLOCK_SIZE


@dataclass
class Stats:
    blocks: int = 0
    payload_bytes: int = 0
    overflow_count: int = 0
    dropped_bytes: int = 0
    buffer_used: int = 0
    reconnects: int = 0
    slow_clients: int = 0
    last_error: str = ""
    started_at: float = 0.0


class Bridge:
    def __init__(self, backend: JtagBackend, identity: TargetIdentity, *,
                 block_size: int = 1024, queue_depth: int = 64,
                 capture: Path | None = None) -> None:
        self.backend = backend
        self.identity = identity
        self.block_size = block_size
        self.queue_depth = queue_depth
        self.capture_path = capture
        self.stats = Stats(started_at=time.monotonic())
        self.session_id = 0
        self._clients: set[asyncio.Queue[bytes | None]] = set()
        self._capture = None
        self._metadata = None
        self._stopping = False

    async def _backend_call(self, method, *args):
        # The mock is deliberately synchronous and non-blocking. Keeping it on
        # the event-loop thread also makes --self-test independent of threads.
        if isinstance(self.backend, MockBackend):
            return method(*args)
        return await asyncio.to_thread(method, *args)

    async def start(self) -> None:
        await self._backend_call(self.backend.open, self.identity)
        if self.capture_path:
            self._capture = self.capture_path.open("ab")
            self._metadata = self.capture_path.with_suffix(
                self.capture_path.suffix + ".jsonl").open("a", encoding="utf-8")

    async def close(self) -> None:
        self._stopping = True
        for queue in tuple(self._clients):
            self._disconnect(queue)
        await self._backend_call(self.backend.close)
        if self._capture:
            self._capture.close()
        if self._metadata:
            self._metadata.close()

    def _disconnect(self, queue: asyncio.Queue[bytes | None]) -> None:
        self._clients.discard(queue)
        while not queue.empty():
            queue.get_nowait()
        queue.put_nowait(None)

    def _broadcast(self, record: bytes) -> None:
        for queue in tuple(self._clients):
            try:
                queue.put_nowait(record)
            except asyncio.QueueFull:
                self.stats.slow_clients += 1
                self._disconnect(queue)

    async def client(self, _reader: asyncio.StreamReader,
                     writer: asyncio.StreamWriter) -> None:
        await self._record_client(writer, websocket=False)

    async def websocket_client(self, reader: asyncio.StreamReader,
                               writer: asyncio.StreamWriter) -> None:
        """Serve the bridge protocol as binary WebSocket messages for Web Viewer."""
        try:
            request = await asyncio.wait_for(reader.readuntil(b"\r\n\r\n"), 5.0)
            lines = request.decode("latin1").split("\r\n")
            headers = {}
            for line in lines[1:]:
                if ":" in line:
                    key, value = line.split(":", 1)
                    headers[key.strip().lower()] = value.strip()
            key = headers.get("sec-websocket-key")
            if not lines[0].startswith("GET ") or not key:
                raise ValueError("invalid WebSocket handshake")
            accept = base64.b64encode(hashlib.sha1(
                (key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode("ascii")
            ).digest()).decode("ascii")
            writer.write(("HTTP/1.1 101 Switching Protocols\r\n"
                          "Upgrade: websocket\r\nConnection: Upgrade\r\n"
                          f"Sec-WebSocket-Accept: {accept}\r\n\r\n").encode("ascii"))
            await writer.drain()
            await self._record_client(writer, websocket=True)
        except (ValueError, asyncio.IncompleteReadError, asyncio.TimeoutError,
                ConnectionError, asyncio.CancelledError):
            writer.close()
            try:
                await writer.wait_closed()
            except ConnectionError:
                pass

    @staticmethod
    def _websocket_frame(payload: bytes) -> bytes:
        length = len(payload)
        if length < 126:
            header = bytes((0x82, length))
        elif length < 65536:
            header = bytes((0x82, 126)) + length.to_bytes(2, "big")
        else:
            header = bytes((0x82, 127)) + length.to_bytes(8, "big")
        return header + payload

    async def _record_client(self, writer: asyncio.StreamWriter, *, websocket: bool) -> None:
        queue: asyncio.Queue[bytes | None] = asyncio.Queue(self.queue_depth)
        self._clients.add(queue)
        encode = self._websocket_frame if websocket else (lambda value: value)
        try:
            writer.write(encode(hello(self.identity, self.session_id)))
            await writer.drain()
            while True:
                record = await queue.get()
                if record is None:
                    break
                writer.write(encode(record))
                await writer.drain()
        except (ConnectionError, asyncio.CancelledError):
            pass
        finally:
            self._clients.discard(queue)
            writer.close()
            try:
                await writer.wait_closed()
            except ConnectionError:
                pass

    def _read_transaction(self):
        """Read and commit one mailbox block in a single worker dispatch."""
        header = self.backend.read_header()
        if header.build_id != self.identity.build_id:
            raise RuntimeError("target build identity changed")
        if not header.available_bytes:
            return header, None
        length = min(header.available_bytes, self.block_size)
        block = self.backend.read_block(length)
        if (block.session_id != header.session_id or
                block.start_count != header.read_count or len(block.data) != length):
            raise RuntimeError("stale or short mailbox block")
        self.backend.commit(block)
        return header, block

    async def pump_once(self) -> int:
        header, block = await self._backend_call(self._read_transaction)
        if header.session_id != self.session_id:
            old = self.session_id
            self.session_id = header.session_id
            self._broadcast(json_frame(TYPE_SESSION, {"old": old, "new": self.session_id}))
        self.stats.overflow_count = header.overflow_count
        self.stats.dropped_bytes = header.dropped_bytes
        self.stats.buffer_used = header.available_bytes
        if block is None:
            return 0
        if self._capture:
            self._capture.write(block.data)
            self._capture.flush()
            self._metadata.write(json.dumps({"time": time.time(), "session_id": block.session_id,
                                             "start_count": block.start_count,
                                             "length": len(block.data)}) + "\n")
            self._metadata.flush()
        self.stats.blocks += 1
        self.stats.payload_bytes += len(block.data)
        self._broadcast(data_frame(block.data))
        return len(block.data)

    async def pump(self, idle_interval: float) -> None:
        backoff = idle_interval
        while not self._stopping:
            try:
                if not await self.pump_once():
                    await asyncio.sleep(idle_interval)
                self.stats.last_error = ""
                backoff = idle_interval
            except Exception as exc:
                self.stats.last_error = str(exc)
                try:
                    await asyncio.sleep(min(1.0, backoff))
                    await self.reconnect_once()
                except Exception as reconnect_error:
                    self.stats.last_error = str(reconnect_error)
                backoff = min(1.0, max(idle_interval, backoff * 2))

    async def reconnect_once(self) -> None:
        await self._backend_call(self.backend.close)
        targets = await self._backend_call(self.backend.enumerate)
        matches = [item for item in targets if item == self.identity]
        if len(matches) != 1:
            raise TargetSelectionError("original target identity is not uniquely present")
        await self._backend_call(self.backend.open, matches[0])
        # Header validation is part of reconnect, not deferred until consumption.
        header = await self._backend_call(self.backend.read_header)
        if header.build_id != self.identity.build_id:
            await self._backend_call(self.backend.close)
            raise TargetSelectionError("target build identity changed during reconnect")
        self.stats.reconnects += 1
        self.stats.last_error = ""

    async def publish_status(self, interval: float) -> None:
        while not self._stopping:
            await asyncio.sleep(interval)
            self._broadcast(self.status_record())

    def status_record(self) -> bytes:
        value = asdict(self.stats)
        elapsed = max(time.monotonic() - self.stats.started_at, 1e-9)
        value["bytes_per_second"] = self.stats.payload_bytes / elapsed
        value["clients"] = len(self._clients)
        return json_frame(TYPE_STATUS, value)


def select_target(targets: list[TargetIdentity], selector: str | None) -> TargetIdentity:
    if selector:
        matches = [target for target in targets if target.stable_id == selector]
        if len(matches) != 1:
            raise TargetSelectionError(f"target selector matched {len(matches)} targets")
        return matches[0]
    if len(targets) != 1:
        choices = "\n".join(f"  {target.stable_id}" for target in targets)
        raise TargetSelectionError("multiple/no targets; pass --target with one of:\n" + choices)
    return targets[0]


async def run(args: argparse.Namespace) -> None:
    if args.backend == "mock":
        backend: JtagBackend = MockBackend()
    elif args.backend == "ftdi":
        from ftdi_backend import FtdiMpsseBackend
        backend = FtdiMpsseBackend(args.ftdi_vendor, args.ftdi_product,
                                   tck_hz=args.tck_hz, build_id=args.build_id)
    else:
        from xilinx_hw_server_backend import XilinxHardwareBackend
        backend = XilinxHardwareBackend(args.vivado)
    targets = await asyncio.to_thread(backend.enumerate)
    if args.list_targets:
        for target in targets:
            print(target.stable_id)
        return
    identity = select_target(targets, args.target)
    bridge = Bridge(backend, identity, block_size=args.block_size,
                    queue_depth=args.queue_depth, capture=args.capture)
    await bridge.start()
    server = await asyncio.start_server(bridge.client, args.host, args.port)
    websocket_server = await asyncio.start_server(
        bridge.websocket_client, args.host, args.websocket_port)
    stop = asyncio.Event()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(sig, stop.set)
        except NotImplementedError:
            pass
    pump = asyncio.create_task(bridge.pump(args.idle_interval))
    status = asyncio.create_task(bridge.publish_status(args.status_interval))
    try:
        async with server, websocket_server:
            await stop.wait()
    finally:
        pump.cancel()
        status.cancel()
        await asyncio.gather(pump, status, return_exceptions=True)
        await bridge.close()


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--backend", choices=("mock", "xilinx", "ftdi"), default="mock")
    p.add_argument("--target", help="exact stable target identity")
    p.add_argument("--list-targets", action="store_true")
    p.add_argument("--host", default="127.0.0.1")
    p.add_argument("--port", type=int, default=48534)
    p.add_argument("--websocket-port", type=int, default=48535,
                   help="local Web Viewer WebSocket port")
    p.add_argument("--block-size", type=int, default=DEFAULT_MAX_BLOCK_SIZE)
    p.add_argument("--queue-depth", type=int, default=64)
    p.add_argument("--idle-interval", type=float, default=0.01)
    p.add_argument("--status-interval", type=float, default=1.0)
    p.add_argument("--capture", type=Path)
    p.add_argument("--vivado", default="vivado")
    p.add_argument("--ftdi-vendor", type=lambda value: int(value, 0), default=0x0403)
    p.add_argument("--ftdi-product", type=lambda value: int(value, 0), default=0x6014)
    p.add_argument("--tck-hz", type=int, default=6_000_000)
    p.add_argument("--build-id", type=lambda value: int(value, 0), default=0x4D340001)
    p.add_argument("--self-test", action="store_true")
    return p


def main() -> int:
    args = parser().parse_args()
    if not 1 <= args.block_size <= DEFAULT_MAX_BLOCK_SIZE:
        parser().error("--block-size must be in 1..1024")
    if args.queue_depth < 1:
        parser().error("--queue-depth must be positive")
    if args.idle_interval <= 0 or args.status_interval <= 0:
        parser().error("poll and status intervals must be positive")
    if not 1_000 <= args.tck_hz <= 30_000_000:
        parser().error("--tck-hz must be in 1000..30000000")
    if args.self_test:
        import unittest
        suite = unittest.defaultTestLoader.discover(str(Path(__file__).parent),
                                                     pattern="test_jtag_bridge.py")
        return 0 if unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful() else 1
    try:
        asyncio.run(run(args))
    except (TargetSelectionError, OSError) as exc:
        print(f"bridge: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
