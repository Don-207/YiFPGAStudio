"""Minimal FT232H MPSSE JTAG scanner used for M34 board validation.

Uses the system libftdi1 through ctypes, so no Python package is required.
"""
from __future__ import annotations

import ctypes
import ctypes.util
import time
from dataclasses import dataclass


class FtdiError(RuntimeError):
    pass


@dataclass(frozen=True)
class _MpssePiece:
    command: bytes
    scan: int
    read_length: int = 0


class FtdiMpsseJtag:
    # Keep the FT232H IN FIFO draining, but make each USB exchange large enough
    # to amortize libusb/latency-timer overhead. 251 also lets a four-byte
    # command scan (five raw MPSSE samples including the exit bit) share the
    # first 256-byte exchange with a payload scan.
    _MAX_BATCH_READ = 256
    _MAX_DATA_PIECE = 251

    @staticmethod
    def clock_divisor(tck_hz: int) -> int:
        if not 1_000 <= tck_hz <= 30_000_000:
            raise ValueError("tck_hz must be in 1 kHz..30 MHz")
        return max(0, min(0xFFFF, round(60_000_000 / (2 * tck_hz) - 1)))

    def __init__(self, vendor: int = 0x0403, product: int = 0x6014,
                 tck_hz: int = 6_000_000) -> None:
        divisor = self.clock_divisor(tck_hz)
        name = ctypes.util.find_library("ftdi1") or "libftdi1.so.2"
        self.lib = ctypes.CDLL(name)
        self.lib.ftdi_new.restype = ctypes.c_void_p
        self.lib.ftdi_free.argtypes = [ctypes.c_void_p]
        self.lib.ftdi_usb_open.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int]
        self.lib.ftdi_usb_close.argtypes = [ctypes.c_void_p]
        self.lib.ftdi_usb_reset.argtypes = [ctypes.c_void_p]
        self.lib.ftdi_get_error_string.argtypes = [ctypes.c_void_p]
        self.lib.ftdi_get_error_string.restype = ctypes.c_char_p
        self.lib.ftdi_set_bitmode.argtypes = [ctypes.c_void_p, ctypes.c_ubyte, ctypes.c_ubyte]
        self.lib.ftdi_set_latency_timer.argtypes = [ctypes.c_void_p, ctypes.c_ubyte]
        self.lib.ftdi_write_data.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_int]
        self.lib.ftdi_read_data.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_int]
        self.ctx = self.lib.ftdi_new()
        if not self.ctx:
            raise FtdiError("ftdi_new failed")
        if self.lib.ftdi_usb_open(self.ctx, vendor, product) < 0:
            self.close()
            raise FtdiError(f"FTDI {vendor:04x}:{product:04x} open failed")
        self.lib.ftdi_usb_reset(self.ctx)
        self.lib.ftdi_set_latency_timer(self.ctx, 1)
        if self.lib.ftdi_set_bitmode(self.ctx, 0, 0) < 0:
            raise FtdiError("failed to reset FTDI bit mode")
        if self.lib.ftdi_set_bitmode(self.ctx, 0x0B, 0x02) < 0:
            raise FtdiError("failed to enable MPSSE")
        time.sleep(0.05)
        # 60 MHz MPSSE clock, no divide-by-5/adaptive/three-phase clocking.
        # TCK = 60 MHz / (2 * (1 + divisor)). Low GPIO:
        # TCK=0, TDI=0, TMS=1; TDO is input.
        self.tck_hz = 60_000_000 / (2 * (1 + divisor))
        self._write(bytes((0x8A, 0x97, 0x8D, 0x86, divisor & 0xff,
                           divisor >> 8, 0x80, 0x08, 0x0B)))
        self.tap_reset()
        self.select_user2()

    def close(self) -> None:
        if getattr(self, "ctx", None):
            self.lib.ftdi_set_bitmode(self.ctx, 0, 0)
            self.lib.ftdi_usb_close(self.ctx)
            self.lib.ftdi_free(self.ctx)
            self.ctx = None

    def _write(self, data: bytes) -> None:
        buf = ctypes.create_string_buffer(data)
        offset = 0
        while offset < len(data):
            # The Digilent FT232H endpoint has a 512-byte HS bulk packet. Some
            # libftdi builds fail instead of internally splitting larger writes.
            requested = min(512, len(data)-offset)
            count = self.lib.ftdi_write_data(self.ctx, ctypes.byref(buf, offset), requested)
            if count <= 0:
                message = self.lib.ftdi_get_error_string(self.ctx).decode(errors="replace")
                raise FtdiError(f"FTDI write failed at {offset}/{len(data)} ({count}): {message}")
            offset += count

    def _read(self, length: int, timeout: float = 2.0) -> bytes:
        result = bytearray()
        deadline = time.monotonic() + timeout
        while len(result) < length and time.monotonic() < deadline:
            buf = ctypes.create_string_buffer(length-len(result))
            count = self.lib.ftdi_read_data(self.ctx, buf, len(buf))
            if count < 0:
                raise FtdiError("FTDI read failed")
            result.extend(buf.raw[:count])
            if not count:
                time.sleep(0.001)
        if len(result) != length:
            raise FtdiError(f"FTDI short read: {len(result)}/{length}")
        return bytes(result)

    def _tms(self, bits: int, count: int, *, read: bool = False, tdi: int = 0) -> int:
        # Read TDO on the falling edge, after the FPGA TCK-domain state has
        # settled from its rising-edge update.
        command = 0x6F if read else 0x4B
        self._write(bytes((command, count-1, (bits & 0x7f) | ((tdi & 1) << 7), 0x87)))
        return self._read(1)[0] if read else 0

    @staticmethod
    def _scan_pieces(outgoing: bytes, total: int, scan: int) -> list[_MpssePiece]:
        """Encode one complete DR transaction without forcing USB boundaries."""
        pieces = [_MpssePiece(bytes((0x4B, 2, 0b001)), scan)]
        body = total - 1
        full, rem = divmod(body, 8)
        offset = 0
        while offset < full:
            width = min(FtdiMpsseJtag._MAX_DATA_PIECE, full - offset)
            pieces.append(_MpssePiece(
                bytes((0x3D, (width - 1) & 0xff, (width - 1) >> 8))
                + outgoing[offset:offset + width], scan, width))
            offset += width
        if rem:
            pieces.append(_MpssePiece(bytes((0x3F, rem - 1, outgoing[full])), scan, 1))
        final_tdi = (outgoing[(total - 1) // 8] >> ((total - 1) & 7)) & 1
        pieces.append(_MpssePiece(bytes((0x6F, 0, 1 | (final_tdi << 7))), scan, 1))
        pieces.append(_MpssePiece(bytes((0x4B, 1, 0b01)), scan))
        return pieces

    def _scan_many(self, scans: list[tuple[bytes, int]]) -> list[bytes]:
        """Run adjacent DR scans in bounded, pipelined MPSSE/USB batches."""
        pieces: list[_MpssePiece] = []
        raw = [bytearray() for _ in scans]
        for index, (outgoing, total) in enumerate(scans):
            if total < 1 or total > len(outgoing) * 8:
                raise ValueError("invalid scan bit count")
            pieces.extend(self._scan_pieces(outgoing, total, index))

        batch: list[_MpssePiece] = []
        pending = 0

        def flush() -> None:
            nonlocal batch, pending
            if not batch:
                return
            command = b"".join(piece.command for piece in batch)
            if pending:
                command += bytes((0x87,))
            self._write(command)
            incoming = self._read(pending) if pending else b""
            offset = 0
            for piece in batch:
                end = offset + piece.read_length
                raw[piece.scan].extend(incoming[offset:end])
                offset = end
            batch = []
            pending = 0

        for piece in pieces:
            if pending and pending + piece.read_length > self._MAX_BATCH_READ:
                flush()
            batch.append(piece)
            pending += piece.read_length
        flush()

        results: list[bytes] = []
        for index, (_, total) in enumerate(scans):
            full, rem = divmod(total - 1, 8)
            incoming = raw[index]
            result = bytearray((total + 7) // 8)
            result[:full] = incoming[:full]
            pos = full
            if rem:
                result[full] = incoming[pos] >> (8 - rem)
                pos += 1
            result[(total - 1) // 8] |= ((incoming[pos] >> 7) & 1) << ((total - 1) & 7)
            results.append(bytes(result))
        return results

    def tap_reset(self) -> None:
        self._tms(0x1F, 5)
        self._tms(0, 1)

    def select_user2(self) -> None:
        # UltraScale JTAG IR is 6 bits; USER2 instruction is 6'b000011.
        self._tms(0b0011, 4)  # Idle -> Select-DR -> Select-IR -> Capture-IR -> Shift-IR
        # Shift the first five instruction bits (LSB first), then the final bit
        # while taking TMS high to Exit1-IR.
        self._write(bytes((0x1B, 4, 0x03)))
        self._tms(1, 1, tdi=0)
        self._tms(0b01, 2)  # Update-IR -> Idle

    def scan_dr(self, outgoing: bytes, bit_count: int | None = None) -> bytes:
        total = len(outgoing) * 8 if bit_count is None else bit_count
        return self._scan_many([(outgoing, total)])[0]

    def user_command(self, opcode: int, length: int) -> bytes:
        request = bytes((0xA6, opcode, length & 0xff, length >> 8))
        # The FPGA sees UPDATE-DR for the request before the following
        # CAPTURE-DR even when both scans are in one MPSSE stream. No host-side
        # wait is required, so pipeline them and discard only the request TDO.
        return self._scan_many([(request, 32), (bytes(length), length * 8)])[1]
