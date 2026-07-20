"""Backend contract and hardware-free backend for the M34 JTAG bridge."""

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Iterable

from mailbox_model import MailboxHeader, MailboxModel, ReadTransaction


class BackendError(RuntimeError):
    """A recoverable backend/transport failure."""


class TargetSelectionError(BackendError):
    """Discovery did not produce one explicitly selected target."""


@dataclass(frozen=True)
class TargetIdentity:
    cable: str
    target: str
    device: str
    user_chain: int
    build_id: int = 0

    @property
    def stable_id(self) -> str:
        return f"{self.cable}/{self.target}/{self.device}/user{self.user_chain}"


@dataclass(frozen=True)
class Block:
    session_id: int
    start_count: int
    data: bytes
    token: object


class JtagBackend(ABC):
    @abstractmethod
    def enumerate(self) -> list[TargetIdentity]: ...

    @abstractmethod
    def open(self, identity: TargetIdentity) -> None: ...

    @abstractmethod
    def read_header(self) -> MailboxHeader: ...

    @abstractmethod
    def read_block(self, length: int) -> Block: ...

    @abstractmethod
    def commit(self, block: Block) -> None: ...

    @abstractmethod
    def close(self) -> None: ...


class MockBackend(JtagBackend):
    """MailboxModel adapter used by self-tests and offline development."""

    def __init__(self, payloads: Iterable[bytes] = (), *, targets: int = 1) -> None:
        self.model = MailboxModel(4096, build_id=0x4D333400)
        self._targets = [
            TargetIdentity("mock-cable", f"mock-target-{i}", f"mock-device-{i}", 1,
                           self.model.build_id)
            for i in range(targets)
        ]
        self._opened: TargetIdentity | None = None
        for payload in payloads:
            self.model.write(payload)

    def enumerate(self) -> list[TargetIdentity]:
        return list(self._targets)

    def open(self, identity: TargetIdentity) -> None:
        if identity not in self._targets:
            raise TargetSelectionError("mock target identity is not present")
        self._opened = identity

    def _require_open(self) -> None:
        if self._opened is None:
            raise BackendError("backend is not open")

    def read_header(self) -> MailboxHeader:
        self._require_open()
        return self.model.header()

    def read_block(self, length: int) -> Block:
        self._require_open()
        tx = self.model.begin_read(length)
        return Block(tx.session_id, tx.start_count, tx.data, tx)

    def commit(self, block: Block) -> None:
        self._require_open()
        if not isinstance(block.token, ReadTransaction):
            raise BackendError("invalid mock transaction token")
        self.model.commit(block.token)

    def close(self) -> None:
        self._opened = None
