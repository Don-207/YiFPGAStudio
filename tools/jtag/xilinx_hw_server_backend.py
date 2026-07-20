"""Persistent Vivado Hardware Manager backend.

The Tcl worker speaks a deliberately small tab-separated protocol on stdin/stdout.
No target value is ever interpolated into Tcl source code.
"""

from __future__ import annotations

from pathlib import Path
import subprocess

from jtag_backend import BackendError, Block, JtagBackend, TargetIdentity
from mailbox_model import MailboxHeader


class XilinxHardwareBackend(JtagBackend):
    def __init__(self, vivado: str = "vivado") -> None:
        self.vivado = vivado
        self._process: subprocess.Popen[str] | None = None
        self._identity: TargetIdentity | None = None
        self._last_block: Block | None = None

    def _start(self) -> None:
        if self._process and self._process.poll() is None:
            return
        script = Path(__file__).parents[2] / "prj/scripts/yifpga_jtag_read.tcl"
        self._process = subprocess.Popen(
            [self.vivado, "-mode", "tcl", "-nolog", "-nojournal", "-source", str(script)],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, bufsize=1, shell=False,
        )

    def _command(self, *fields: object) -> list[str]:
        self._start()
        assert self._process and self._process.stdin and self._process.stdout
        if any("\t" in str(field) or "\n" in str(field) for field in fields):
            raise BackendError("invalid backend command field")
        self._process.stdin.write("\t".join(map(str, fields)) + "\n")
        self._process.stdin.flush()
        while True:
            line = self._process.stdout.readline()
            if not line:
                error = self._process.stderr.read() if self._process.stderr else ""
                raise BackendError("Vivado worker exited: " + error[-1000:])
            line = line.rstrip("\r\n")
            if line.startswith("OFJT\t"):
                result = line.split("\t")
                if len(result) >= 2 and result[1] == "ERR":
                    raise BackendError(" ".join(result[2:]))
                return result[2:]

    def enumerate(self) -> list[TargetIdentity]:
        count_fields = self._command("DISCOVER")
        if len(count_fields) != 1:
            raise BackendError("invalid discovery response")
        count = int(count_fields[0])
        result = []
        for index in range(count):
            fields = self._command("TARGET", index)
            if len(fields) != 5:
                raise BackendError("invalid target response")
            result.append(TargetIdentity(fields[0], fields[1], fields[2],
                                         int(fields[3]), int(fields[4], 0)))
        return result

    def open(self, identity: TargetIdentity) -> None:
        self._command("OPEN", identity.cable, identity.target, identity.device,
                      identity.user_chain, identity.build_id)
        self._identity = identity

    def read_header(self) -> MailboxHeader:
        raw = bytes.fromhex(self._command("HEADER")[0])
        return MailboxHeader.unpack(raw)

    def read_block(self, length: int) -> Block:
        fields = self._command("READ", length)
        if len(fields) != 3:
            raise BackendError("invalid block response")
        block = Block(int(fields[0], 0), int(fields[1], 0), bytes.fromhex(fields[2]), None)
        if len(block.data) != length:
            raise BackendError("short block read")
        self._last_block = block
        return block

    def commit(self, block: Block) -> None:
        if block is not self._last_block:
            raise BackendError("commit does not match last block")
        self._command("COMMIT", block.session_id, block.start_count, len(block.data))
        self._last_block = None

    def close(self) -> None:
        process, self._process = self._process, None
        self._identity = None
        self._last_block = None
        if process and process.poll() is None:
            try:
                if process.stdin:
                    process.stdin.write("QUIT\n")
                    process.stdin.flush()
                process.wait(timeout=5)
            except (BrokenPipeError, subprocess.TimeoutExpired):
                process.terminate()
                try:
                    process.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    process.kill()

    def __enter__(self) -> "XilinxHardwareBackend":
        return self

    def __exit__(self, *_args: object) -> None:
        self.close()
