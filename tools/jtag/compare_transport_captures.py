#!/usr/bin/env python3
"""Compare UART and JTAG raw Debug Protocol captures after frame alignment."""

from __future__ import annotations

import argparse
from collections import Counter
from difflib import SequenceMatcher
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).parents[1] / "viewer"))
from validate_uart_board import Decoder, TYPE_NAMES, make_frame


def decode(path: Path) -> tuple[Decoder, list[bytes]]:
    decoder = Decoder()
    decoder.feed(path.read_bytes())
    return decoder, [make_frame(kind, payload) for kind, payload in decoder.frames]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("uart", type=Path)
    parser.add_argument("jtag", type=Path)
    parser.add_argument("--min-common-ratio", type=float, default=0.99)
    args = parser.parse_args()
    uart_decoder, uart_frames = decode(args.uart)
    jtag_decoder, jtag_frames = decode(args.jtag)
    matcher = SequenceMatcher(None, uart_frames, jtag_frames, autojunk=False)
    matching = sum(block.size for block in matcher.get_matching_blocks())
    denominator = max(1, min(len(uart_frames), len(jtag_frames)))
    ratio = matching / denominator
    uart_types = Counter(TYPE_NAMES.get(frame[2], f"0x{frame[2]:02x}")
                         for frame in uart_frames)
    jtag_types = Counter(TYPE_NAMES.get(frame[2], f"0x{frame[2]:02x}")
                         for frame in jtag_frames)
    print(f"uart_frames={len(uart_frames)} jtag_frames={len(jtag_frames)} "
          f"matching_frames={matching} common_ratio={ratio:.6f}")
    print(f"uart_checksum_errors={uart_decoder.checksum_errors} "
          f"jtag_checksum_errors={jtag_decoder.checksum_errors} "
          f"uart_version_errors={uart_decoder.version_errors} "
          f"jtag_version_errors={jtag_decoder.version_errors}")
    print(f"uart_types={dict(sorted(uart_types.items()))}")
    print(f"jtag_types={dict(sorted(jtag_types.items()))}")
    failures = []
    if uart_decoder.checksum_errors or uart_decoder.version_errors:
        failures.append("UART protocol errors")
    if jtag_decoder.checksum_errors or jtag_decoder.version_errors:
        failures.append("JTAG protocol errors")
    if ratio < args.min_common_ratio:
        failures.append(f"common ratio {ratio:.6f} below {args.min_common_ratio:.6f}")
    if failures:
        raise RuntimeError("; ".join(failures))
    print("PASS: UART/JTAG frame sequences are equivalent after window alignment")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
