#!/usr/bin/env python3
"""Hardware-free tests for the direct FTDI Bridge backend."""

from __future__ import annotations

import unittest

from ftdi_backend import FtdiMpsseBackend
from jtag_backend import BackendError
from mailbox_model import MailboxModel


class FakeScanner:
    model = MailboxModel(4096, build_id=0x4D340001)

    def __init__(self, **configuration) -> None:
        self.configuration = configuration
        self.closed = False

    def user_command(self, opcode: int, length: int) -> bytes:
        if opcode == 1:
            return self.model.header().pack()
        if opcode == 2:
            transaction = self.model.begin_read(length)
            self.model.commit(transaction)
            return transaction.data
        raise AssertionError(opcode)

    def close(self) -> None:
        self.closed = True


class FtdiBackendTest(unittest.TestCase):
    def setUp(self) -> None:
        FakeScanner.model = MailboxModel(4096, build_id=0x4D340001)

    def backend(self) -> FtdiMpsseBackend:
        return FtdiMpsseBackend(scanner_factory=FakeScanner)

    def test_payload_scan_maps_to_bridge_commit_contract(self) -> None:
        expected = bytes(range(128))
        FakeScanner.model.write(expected)
        backend = self.backend()
        identity = backend.enumerate()[0]
        backend.open(identity)
        before = backend.read_header()
        block = backend.read_block(128)
        self.assertEqual(block.data, expected)
        self.assertEqual(block.start_count, before.read_count)
        backend.commit(block)
        after = backend.read_header()
        self.assertEqual(after.read_count - before.read_count, 128)
        backend.close()

    def test_build_identity_mismatch_is_rejected(self) -> None:
        backend = FtdiMpsseBackend(build_id=0xDEADBEEF, scanner_factory=FakeScanner)
        with self.assertRaises(BackendError):
            backend.open(backend.enumerate()[0])

    def test_uncommitted_block_prevents_second_read(self) -> None:
        FakeScanner.model.write(b"abcdefgh")
        backend = self.backend()
        backend.open(backend.enumerate()[0])
        backend.read_header()
        backend.read_block(4)
        with self.assertRaises(BackendError):
            backend.read_block(4)
        backend.close()


if __name__ == "__main__":
    unittest.main(verbosity=2)
