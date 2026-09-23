#!/usr/bin/env python3
"""Regression test for spinner redraw inside a real interactive zsh ZLE widget."""
import json
import os
import pathlib
import pty
import select
import shutil
import signal
import tempfile
import time

root = pathlib.Path(__file__).resolve().parent.parent
command = "printf '%s\\n' 'i like eggs' 'i like eggs' 'i like eggs'"


def read_until(fd: int, marker: bytes, timeout: float = 5) -> bytes:
    data = bytearray()
    deadline = time.monotonic() + timeout
    while marker not in data and time.monotonic() < deadline:
        if select.select([fd], [], [], 0.05)[0]:
            data.extend(os.read(fd, 65536))
    assert marker in data, bytes(data)
    return bytes(data)


def read_for(fd: int, seconds: float) -> bytes:
    data = bytearray()
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if select.select([fd], [], [], 0.05)[0]:
            data.extend(os.read(fd, 65536))
    return bytes(data)


with tempfile.TemporaryDirectory() as temp:
    home = pathlib.Path(temp)
    (home / "bin").mkdir()
    fake_curl = home / "bin/curl"
    shutil.copy(root / "tests/helpers/fake-curl", fake_curl)
    fake_curl.chmod(0o755)
    response = home / "response.json"
    response.write_text(json.dumps({"status": "completed", "output": [{"content": [{"type": "output_text", "text": command}]}]}))

    pid, terminal = pty.fork()
    if pid == 0:
        os.environ.update(
            HOME=temp,
            ZDOTDIR=temp,
            PATH=f"{home / 'bin'}:{root / 'bin'}:{os.environ['PATH']}",
            OPENAI_API_KEY="test_key_secret_123",
            FAKE_EXPECT_KEY="test_key_secret_123",
            FAKE_RESPONSE=str(response),
            FAKE_PAYLOAD_COPY=str(home / "payload.json"),
            FAKE_CURL_DELAY="0.5",
            TERM="xterm-256color",
        )
        os.execv("/bin/zsh", ["zsh", "-f", "-i"])

    try:
        read_until(terminal, b"% ")
        os.write(terminal, f"PROMPT='bengirone@Mac ~ %% '; source {root}/integrations/zsh-integration.zsh\n".encode())
        read_until(terminal, b"bengirone@Mac ~ % ")

        os.write(terminal, b"say i like eggs three times\x07")
        rewritten = read_until(terminal, f"bengirone@Mac ~ % {command}".encode())
        assert b"ai-shell: waiting" in rewritten
        assert b"\r\ni like eggs\r\n" not in rewritten  # Still unexecuted.

        os.write(terminal, b"\n")
        executed = read_until(terminal, b"i like eggs\r\ni like eggs\r\ni like eggs\r\n")
        assert b"i like eggs\r\ni like eggs\r\ni like eggs\r\n" in executed

        # Enter typed before the API returns must not execute the new command.
        read_until(terminal, b"bengirone@Mac ~ % ")
        os.write(terminal, b"say i like eggs three times\x07\n")
        early = read_until(terminal, f"bengirone@Mac ~ % {command}".encode())
        early += read_for(terminal, 0.3)
        assert b"\r\ni like eggs\r\n" not in early, early
        os.write(terminal, b"\n")
        executed_again = read_until(terminal, b"i like eggs\r\ni like eggs\r\ni like eggs\r\n")

        # A queued Enter must not execute the original request after an API failure.
        if b"bengirone@Mac ~ % " not in executed_again:
            read_until(terminal, b"bengirone@Mac ~ % ")
        response.write_text(json.dumps({"status": "incomplete", "incomplete_details": {"reason": "max_output_tokens"}, "output": []}))
        os.write(terminal, b"please rewrite this\x07\n")
        failed = read_until(terminal, b"ai-shell: response incomplete: max_output_tokens")
        failed += read_for(terminal, 0.3)
        assert b"command not found: please" not in failed, failed
        assert b"bengirone@Mac ~ % please rewrite this" in failed, failed
    finally:
        os.kill(pid, signal.SIGKILL)
        os.close(terminal)

print("PASS zsh spinner redraw and queued Enter safety")
