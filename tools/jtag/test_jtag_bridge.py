from __future__ import annotations

import asyncio
import json
from pathlib import Path
import tempfile
import unittest

from bridge_protocol import TYPE_DATA, TYPE_HELLO, data_frame, decode_records, hello
from jtag_backend import MockBackend, TargetSelectionError
import yifpga_jtag_bridge as canonical_bridge
from yifpga_jtag_bridge import Bridge, select_target


FIXTURE = Path(__file__).with_name("fixtures") / "m32_mailbox_vectors.json"



class BridgeProtocolTest(unittest.TestCase):
    def test_fragmented_records_preserve_payload(self) -> None:
        payload = bytes(range(256))
        encoded = data_frame(payload)
        records, rest = decode_records(encoded[:7])
        self.assertEqual(records, [])
        records, rest = decode_records(rest + encoded[7:])
        self.assertEqual(records, [(TYPE_DATA, payload)])
        self.assertEqual(rest, b"")

    def test_hello_is_versioned_and_identifies_target(self) -> None:
        backend = MockBackend()
        identity = backend.enumerate()[0]
        records, rest = decode_records(hello(identity, 7))
        self.assertFalse(rest)
        self.assertEqual(records[0][0], TYPE_HELLO)
        value = json.loads(records[0][1])
        self.assertEqual(value["bridge_version"], 1)
        self.assertEqual(value["session_id"], 7)
        self.assertEqual(value["stable_id"], identity.stable_id)

    def test_multiple_targets_require_selector(self) -> None:
        targets = MockBackend(targets=2).enumerate()
        with self.assertRaises(TargetSelectionError):
            select_target(targets, None)
        self.assertEqual(select_target(targets, targets[1].stable_id), targets[1])


class BridgePumpTest(unittest.IsolatedAsyncioTestCase):
    async def test_websocket_binary_frame_preserves_bridge_record(self) -> None:
        backend = MockBackend()
        bridge = Bridge(backend, backend.enumerate()[0])
        record = hello(backend.enumerate()[0], 9)
        encoded = bridge._websocket_frame(record)
        self.assertEqual(encoded[0], 0x82)
        self.assertEqual(encoded[1], 126)
        length = int.from_bytes(encoded[2:4], "big")
        payload = encoded[4:4 + length]
        records, rest = decode_records(payload)
        self.assertFalse(rest)
        self.assertEqual(records[0][0], TYPE_HELLO)

    async def test_fixture_is_committed_and_captured_byte_exact(self) -> None:
        vectors = json.loads(FIXTURE.read_text(encoding="utf-8"))
        payload = b"".join(bytes.fromhex(item["hex"])
                           for item in vectors["debug_protocol_frames"])
        backend = MockBackend([payload])
        identity = backend.enumerate()[0]
        with tempfile.TemporaryDirectory() as directory:
            capture = Path(directory) / "raw.bin"
            bridge = Bridge(backend, identity, block_size=17, capture=capture)
            await bridge.start()
            while await bridge.pump_once():
                pass
            await bridge.close()
            self.assertEqual(capture.read_bytes(), payload)
            self.assertEqual(backend.model.available_bytes, 0)
            self.assertEqual(bridge.stats.payload_bytes, len(payload))
            metadata = capture.with_suffix(".bin.jsonl").read_text().splitlines()
            self.assertEqual(sum(json.loads(line)["length"] for line in metadata), len(payload))

    async def test_session_reset_is_observed(self) -> None:
        backend = MockBackend([b"old"])
        bridge = Bridge(backend, backend.enumerate()[0])
        await bridge.start()
        await bridge.pump_once()
        old = bridge.session_id
        backend.model.reset()
        backend.model.write(b"new")
        await bridge.pump_once()
        self.assertNotEqual(bridge.session_id, old)
        await bridge.close()

    async def test_slow_client_queue_is_bounded_and_disconnected(self) -> None:
        backend = MockBackend()
        bridge = Bridge(backend, backend.enumerate()[0], queue_depth=1)
        queue: asyncio.Queue[bytes | None] = asyncio.Queue(1)
        bridge._clients.add(queue)
        bridge._broadcast(b"one")
        bridge._broadcast(b"two")
        self.assertNotIn(queue, bridge._clients)
        self.assertEqual(bridge.stats.slow_clients, 1)
        self.assertIsNone(queue.get_nowait())

    async def test_reconnect_rechecks_stable_identity(self) -> None:
        backend = MockBackend()
        identity = backend.enumerate()[0]
        bridge = Bridge(backend, identity)
        await bridge.start()
        for expected in range(1, 4):
            await bridge.reconnect_once()
            self.assertEqual(bridge.stats.reconnects, expected)
        await bridge.close()

    async def test_thousands_of_blocks_are_byte_exact(self) -> None:
        backend = MockBackend()
        bridge = Bridge(backend, backend.enumerate()[0], block_size=31)
        await bridge.start()
        expected = bytearray()
        for index in range(3000):
            payload = index.to_bytes(4, "little") + bytes([index & 0xff]) * 27
            expected.extend(payload)
            self.assertEqual(backend.model.write(payload), len(payload))
            self.assertEqual(await bridge.pump_once(), len(payload))
        self.assertEqual(bridge.stats.blocks, 3000)
        self.assertEqual(bridge.stats.payload_bytes, len(expected))
        self.assertEqual(backend.model.available_bytes, 0)
        await bridge.close()


if __name__ == "__main__":
    unittest.main(verbosity=2)
