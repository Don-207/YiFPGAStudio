from __future__ import annotations

import json
from pathlib import Path
import unittest

from mailbox_model import (
    DEFAULT_MAX_BLOCK_SIZE,
    EmptyReadError,
    InvalidReadError,
    MailboxError,
    MailboxHeader,
    MailboxModel,
    StaleTransactionError,
    counter_delta,
)


FIXTURE = Path(__file__).with_name("fixtures") / "m32_mailbox_vectors.json"


class MailboxModelTest(unittest.TestCase):
    def test_header_binary_round_trip(self) -> None:
        model = MailboxModel(4096, build_id=0x12345678)
        model.write(b"abc")
        encoded = model.header().pack()
        self.assertEqual(MailboxHeader.unpack(encoded), model.header())

    def test_fixture_round_trip_and_ring_wrap(self) -> None:
        vectors = json.loads(FIXTURE.read_text(encoding="utf-8"))
        model = MailboxModel(4096)
        for vector in vectors["debug_protocol_frames"]:
            payload = bytes.fromhex(vector["hex"])
            self.assertEqual(model.write(payload), len(payload))
            transaction = model.begin_read(len(payload))
            self.assertEqual(transaction.data, payload, vector["name"])
            model.commit(transaction)

        model.write_count = model.read_count = 0xFFFF_FFF8
        payload = bytes(range(32))
        model.write(payload)
        transaction = model.begin_read(len(payload))
        self.assertEqual(transaction.data, payload)
        model.commit(transaction)
        self.assertEqual(model.read_count, 0x18)
        self.assertEqual(model.available_bytes, 0)

    def test_drop_newest_is_visible_and_preserves_old_data(self) -> None:
        model = MailboxModel(4096)
        original = bytes((index & 0xFF) for index in range(4096))
        self.assertEqual(model.write(original), 4096)
        self.assertEqual(model.write(b"new"), 0)
        self.assertEqual(model.header().overflow_count, 1)
        self.assertEqual(model.header().dropped_bytes, 3)
        chunks = []
        while model.available_bytes:
            tx = model.begin_read(min(DEFAULT_MAX_BLOCK_SIZE, model.available_bytes))
            chunks.append(tx.data)
            model.commit(tx)
        self.assertEqual(b"".join(chunks), original)

    def test_read_requires_successful_commit(self) -> None:
        model = MailboxModel(4096)
        model.write(b"abcdef")
        tx = model.begin_read(3)
        self.assertEqual(model.read_count, 0)
        self.assertEqual(model.begin_read(3).data, b"abc")
        model.commit(tx)
        self.assertEqual(model.begin_read(3).data, b"def")
        with self.assertRaises(StaleTransactionError):
            model.commit(tx)

    def test_reset_invalidates_in_flight_transaction(self) -> None:
        model = MailboxModel(4096)
        model.write(b"frame")
        tx = model.begin_read(5)
        old_session = model.session_id
        model.reset()
        self.assertNotEqual(model.session_id, old_session)
        with self.assertRaises(StaleTransactionError):
            model.commit(tx)

    def test_invalid_reads_and_header_are_rejected(self) -> None:
        model = MailboxModel(4096)
        with self.assertRaises(EmptyReadError):
            model.begin_read(1)
        model.write(b"x")
        for length in (0, -1, 1025, 2):
            with self.assertRaises(InvalidReadError):
                model.begin_read(length)
        damaged = bytearray(model.header().pack())
        damaged[0] ^= 0xFF
        with self.assertRaises(MailboxError):
            MailboxHeader.unpack(bytes(damaged))

    def test_modulo_counter_delta(self) -> None:
        self.assertEqual(counter_delta(0x18, 0xFFFF_FFF8), 32)


if __name__ == "__main__":
    unittest.main(verbosity=2)
