#!/usr/bin/env python3
"""Hardware-free regression for FTDI/MPSSE command batching."""

from __future__ import annotations

import unittest

from ftdi_mpsse import FtdiMpsseJtag


class FakeFtdi(FtdiMpsseJtag):
    def __init__(self) -> None:
        self.writes: list[bytes] = []
        self.reads: list[int] = []
        self.next_sample = 0

    def _write(self, data: bytes) -> None:
        self.writes.append(data)

    def _read(self, length: int, timeout: float = 2.0) -> bytes:
        del timeout
        self.reads.append(length)
        result = bytes((self.next_sample + i) & 0xff for i in range(length))
        self.next_sample += length
        return result


class MpsseBatchingTest(unittest.TestCase):
    def test_tck_divisor_is_parameterized_and_bounded(self) -> None:
        self.assertEqual(FtdiMpsseJtag.clock_divisor(6_000_000), 4)
        self.assertEqual(FtdiMpsseJtag.clock_divisor(30_000_000), 0)
        with self.assertRaises(ValueError):
            FtdiMpsseJtag.clock_divisor(0)

    def test_command_and_512_byte_payload_use_three_bounded_exchanges(self) -> None:
        ftdi = FakeFtdi()
        payload = ftdi.user_command(2, 512)

        self.assertEqual(len(payload), 512)
        self.assertEqual(ftdi.reads, [256, 251, 11])
        self.assertEqual(len(ftdi.writes), 3)
        self.assertTrue(all(length <= ftdi._MAX_BATCH_READ for length in ftdi.reads))
        self.assertTrue(all(write.endswith(b"\x87") for write in ftdi.writes))

    def test_non_byte_aligned_scan_preserves_result_width(self) -> None:
        ftdi = FakeFtdi()
        result = ftdi.scan_dr(b"\xa5\x03", 10)

        self.assertEqual(len(result), 2)
        self.assertEqual(ftdi.reads, [3])
        self.assertEqual(len(ftdi.writes), 1)
        self.assertEqual(result[1] & 0xfc, 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
