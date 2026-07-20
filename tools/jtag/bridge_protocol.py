"""Versioned local socket protocol for the M34 bridge.

Every record is ``u8 type + u32le length + payload``. JSON records are UTF-8;
DATA payloads are the original Debug Protocol bytes without re-encoding.
"""

from __future__ import annotations

import json
import struct
from dataclasses import asdict
from typing import Any

from jtag_backend import TargetIdentity

BRIDGE_VERSION = 1
TYPE_HELLO = 1
TYPE_DATA = 2
TYPE_STATUS = 3
TYPE_SESSION = 4
TYPE_ERROR = 5
HEADER = struct.Struct("<BI")
MAX_RECORD = 16 * 1024 * 1024


class ProtocolError(ValueError):
    pass


def frame(record_type: int, payload: bytes) -> bytes:
    if not 0 <= record_type <= 255 or len(payload) > MAX_RECORD:
        raise ProtocolError("invalid record")
    return HEADER.pack(record_type, len(payload)) + payload


def json_frame(record_type: int, value: dict[str, Any]) -> bytes:
    return frame(record_type, json.dumps(value, separators=(",", ":"),
                                         sort_keys=True).encode("utf-8"))


def hello(identity: TargetIdentity, session_id: int) -> bytes:
    return json_frame(TYPE_HELLO, {
        "bridge_version": BRIDGE_VERSION,
        "transport_version": 1,
        "target": asdict(identity),
        "stable_id": identity.stable_id,
        "session_id": session_id,
    })


def data_frame(payload: bytes) -> bytes:
    return frame(TYPE_DATA, payload)


def decode_records(data: bytes) -> tuple[list[tuple[int, bytes]], bytes]:
    records: list[tuple[int, bytes]] = []
    offset = 0
    while len(data) - offset >= HEADER.size:
        kind, length = HEADER.unpack_from(data, offset)
        if length > MAX_RECORD:
            raise ProtocolError("record exceeds maximum size")
        end = offset + HEADER.size + length
        if end > len(data):
            break
        records.append((kind, data[offset + HEADER.size:end]))
        offset = end
    return records, data[offset:]
