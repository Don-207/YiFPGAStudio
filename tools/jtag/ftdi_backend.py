"""Direct FT232H/MPSSE backend for the YiFPGA JTAG Bridge."""

from __future__ import annotations

from typing import Callable

from ftdi_mpsse import FtdiMpsseJtag
from jtag_backend import BackendError, Block, JtagBackend, TargetIdentity
from mailbox_model import MailboxHeader


class FtdiMpsseBackend(JtagBackend):
    """Board-specific direct USER2 backend without Vivado/hw_server."""

    def __init__(self, vendor: int = 0x0403, product: int = 0x6014, *,
                 tck_hz: int = 6_000_000, build_id: int = 0x4D340001,
                 scanner_factory: Callable[..., FtdiMpsseJtag] = FtdiMpsseJtag) -> None:
        self.vendor = vendor
        self.product = product
        self.tck_hz = tck_hz
        self.build_id = build_id
        self.scanner_factory = scanner_factory
        self.identity = TargetIdentity(
            f"ftdi:{vendor:04x}:{product:04x}", "direct-mpsse", "xilinx-user-dr", 2,
            build_id)
        self._scanner: FtdiMpsseJtag | None = None
        self._header: MailboxHeader | None = None
        self._last_block: Block | None = None
        self._expected_read_count: int | None = None

    def enumerate(self) -> list[TargetIdentity]:
        # libftdi's simple VID/PID API selects one cable. Presence and FPGA
        # identity are verified by open(), before any payload is consumed.
        return [self.identity]

    def open(self, identity: TargetIdentity) -> None:
        if identity != self.identity:
            raise BackendError("FTDI target identity does not match configuration")
        self.close()
        try:
            self._scanner = self.scanner_factory(
                vendor=self.vendor, product=self.product, tck_hz=self.tck_hz)
            header = MailboxHeader.unpack(self._scanner.user_command(1, 40))
            if header.build_id != self.build_id:
                raise BackendError(
                    f"unexpected build id 0x{header.build_id:08x}; "
                    f"expected 0x{self.build_id:08x}")
            self._header = header
        except Exception:
            self.close()
            raise

    def _require_scanner(self) -> FtdiMpsseJtag:
        if self._scanner is None:
            raise BackendError("FTDI backend is not open")
        return self._scanner

    def read_header(self) -> MailboxHeader:
        header = MailboxHeader.unpack(self._require_scanner().user_command(1, 40))
        if header.build_id != self.build_id:
            raise BackendError("target build identity changed")
        if (self._expected_read_count is not None and
                header.read_count != self._expected_read_count):
            raise BackendError(
                f"payload commit mismatch: read_count={header.read_count}, "
                f"expected={self._expected_read_count}")
        self._expected_read_count = None
        self._header = header
        return header

    def read_block(self, length: int) -> Block:
        if self._last_block is not None:
            raise BackendError("previous FTDI block was not committed")
        header = self._header
        if header is None:
            raise BackendError("read_header must precede read_block")
        if length < 1 or length > header.available_bytes:
            raise BackendError("invalid FTDI block length")
        data = self._require_scanner().user_command(2, length)
        if len(data) != length:
            raise BackendError("short FTDI payload scan")
        block = Block(header.session_id, header.read_count, data, object())
        self._last_block = block
        return block

    def commit(self, block: Block) -> None:
        if block is not self._last_block:
            raise BackendError("commit does not match last FTDI block")
        # A complete payload DR UPDATE is the hardware commit boundary. Verify
        # its read_count on the next header scan without adding another scan here.
        self._expected_read_count = (block.start_count + len(block.data)) & 0xFFFF_FFFF
        self._last_block = None

    def close(self) -> None:
        scanner, self._scanner = self._scanner, None
        self._header = None
        self._last_block = None
        self._expected_read_count = None
        if scanner is not None:
            scanner.close()
