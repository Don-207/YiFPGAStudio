"""YiFPGA JTAG Mailbox v1 hardware-free reference model.

This module is the executable contract shared by M33 RTL and M34 Host Bridge.
It deliberately transports opaque bytes and never parses Debug Protocol frames.
"""

from __future__ import annotations

from dataclasses import dataclass
import struct


U32_MASK = 0xFFFF_FFFF
MAGIC = int.from_bytes(b"OFJT", "little")
TRANSPORT_VERSION = 0x0001
CAP_FPGA_TO_HOST = 1 << 0
CAP_BLOCK_READ = 1 << 1
CAP_DROP_NEWEST = 1 << 2
CAP_SESSION_ID = 1 << 3
CAPABILITIES_V1 = (
    CAP_FPGA_TO_HOST | CAP_BLOCK_READ | CAP_DROP_NEWEST | CAP_SESSION_ID
)
HEADER_FORMAT = "<IHHIIIIIIII"
HEADER_SIZE = struct.calcsize(HEADER_FORMAT)
SUPPORTED_BUFFER_SIZES = (4096, 8192, 16384, 32768, 65536)
DEFAULT_MAX_BLOCK_SIZE = 1024


class MailboxError(ValueError):
    """Base class for deterministic mailbox contract violations."""


class EmptyReadError(MailboxError):
    pass


class InvalidReadError(MailboxError):
    pass


class StaleTransactionError(MailboxError):
    pass


def u32(value: int) -> int:
    return value & U32_MASK


def counter_delta(newer: int, older: int) -> int:
    """Return the unsigned modulo-2**32 distance from older to newer."""
    return u32(newer - older)


@dataclass(frozen=True)
class MailboxHeader:
    magic: int = MAGIC
    transport_version: int = TRANSPORT_VERSION
    capabilities: int = CAPABILITIES_V1
    session_id: int = 1
    buffer_size: int = 16384
    write_count: int = 0
    read_count: int = 0
    available_bytes: int = 0
    overflow_count: int = 0
    dropped_bytes: int = 0
    build_id: int = 0

    def pack(self) -> bytes:
        return struct.pack(
            HEADER_FORMAT,
            self.magic,
            self.transport_version,
            self.capabilities,
            self.session_id,
            self.buffer_size,
            self.write_count,
            self.read_count,
            self.available_bytes,
            self.overflow_count,
            self.dropped_bytes,
            self.build_id,
        )

    @classmethod
    def unpack(cls, data: bytes) -> "MailboxHeader":
        if len(data) != HEADER_SIZE:
            raise MailboxError(f"header must be {HEADER_SIZE} bytes")
        header = cls(*struct.unpack(HEADER_FORMAT, data))
        header.validate()
        return header

    def validate(self) -> None:
        if self.magic != MAGIC:
            raise MailboxError("invalid mailbox magic")
        if self.transport_version != TRANSPORT_VERSION:
            raise MailboxError("unsupported transport version")
        if not self.capabilities & CAP_FPGA_TO_HOST:
            raise MailboxError("FPGA-to-Host capability is required")
        if self.buffer_size not in SUPPORTED_BUFFER_SIZES:
            raise MailboxError("unsupported buffer size")
        if self.available_bytes > self.buffer_size:
            raise MailboxError("available_bytes exceeds buffer size")
        if counter_delta(self.write_count, self.read_count) != self.available_bytes:
            raise MailboxError("counter distance disagrees with available_bytes")


@dataclass(frozen=True)
class ReadTransaction:
    session_id: int
    start_count: int
    data: bytes


class MailboxModel:
    """Drop-newest ring buffer with explicit read/commit transactions."""

    def __init__(self, buffer_size: int = 16384, build_id: int = 0) -> None:
        if buffer_size not in SUPPORTED_BUFFER_SIZES:
            raise MailboxError(f"buffer_size must be one of {SUPPORTED_BUFFER_SIZES}")
        self.buffer_size = buffer_size
        self.build_id = u32(build_id)
        self._buffer = bytearray(buffer_size)
        self.session_id = 1
        self.write_count = 0
        self.read_count = 0
        self.overflow_count = 0
        self.dropped_bytes = 0

    @property
    def available_bytes(self) -> int:
        return counter_delta(self.write_count, self.read_count)

    def header(self) -> MailboxHeader:
        return MailboxHeader(
            session_id=self.session_id,
            buffer_size=self.buffer_size,
            write_count=self.write_count,
            read_count=self.read_count,
            available_bytes=self.available_bytes,
            overflow_count=self.overflow_count,
            dropped_bytes=self.dropped_bytes,
            build_id=self.build_id,
        )

    def write(self, data: bytes) -> int:
        accepted = min(len(data), self.buffer_size - self.available_bytes)
        for value in data[:accepted]:
            self._buffer[self.write_count % self.buffer_size] = value
            self.write_count = u32(self.write_count + 1)
        dropped = len(data) - accepted
        if dropped:
            self.overflow_count = u32(self.overflow_count + 1)
            self.dropped_bytes = u32(self.dropped_bytes + dropped)
        return accepted

    def begin_read(self, length: int) -> ReadTransaction:
        if length <= 0 or length > DEFAULT_MAX_BLOCK_SIZE:
            raise InvalidReadError("length must be in 1..1024")
        if not self.available_bytes:
            raise EmptyReadError("mailbox is empty")
        if length > self.available_bytes:
            raise InvalidReadError("short reads are forbidden; request available bytes")
        start = self.read_count
        data = bytes(
            self._buffer[u32(start + offset) % self.buffer_size]
            for offset in range(length)
        )
        return ReadTransaction(self.session_id, start, data)

    def commit(self, transaction: ReadTransaction) -> None:
        if transaction.session_id != self.session_id:
            raise StaleTransactionError("session changed before commit")
        if transaction.start_count != self.read_count:
            raise StaleTransactionError("transaction is stale or already committed")
        if len(transaction.data) > self.available_bytes:
            raise StaleTransactionError("transaction exceeds current availability")
        self.read_count = u32(self.read_count + len(transaction.data))

    def reset(self) -> None:
        self.session_id = u32(self.session_id + 1) or 1
        self.write_count = 0
        self.read_count = 0
        self.overflow_count = 0
        self.dropped_bytes = 0
        self._buffer[:] = bytes(self.buffer_size)
