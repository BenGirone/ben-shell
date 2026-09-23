#!/usr/bin/env python3
"""Exercise the opt-in spinner through a real pseudo-terminal."""
import errno
import os
import pathlib
import pty
import select
import shutil
import subprocess
import tempfile
import time

root = pathlib.Path(__file__).resolve().parent.parent


def run_case(response: str, expected_status: int, expected_stdout: bytes) -> None:
    with tempfile.TemporaryDirectory() as temp:
        temp_path = pathlib.Path(temp)
        fake_bin = temp_path / "bin"
        fake_bin.mkdir()
        fake_curl = fake_bin / "curl"
        shutil.copy(root / "tests/helpers/fake-curl", fake_curl)
        fake_curl.chmod(0o755)
        response_file = temp_path / "response.json"
        response_file.write_text(response)
        env = os.environ.copy()
        env.update(
            PATH=f"{fake_bin}:{env['PATH']}",
            HOME=temp,
            XDG_CONFIG_HOME=temp,
            OPENAI_API_KEY="test_key_secret_123",
            FAKE_EXPECT_KEY="test_key_secret_123",
            FAKE_RESPONSE=str(response_file),
            FAKE_PAYLOAD_COPY=str(temp_path / "payload.json"),
            FAKE_CURL_DELAY="0.5",
        )
        master, slave = pty.openpty()
        process = subprocess.Popen(
            [str(root / "bin/ai-shell"), "--spinner", "--", "find large files"],
            stdin=slave,
            stdout=subprocess.PIPE,
            stderr=slave,
            env=env,
        )
        os.close(slave)
        terminal = bytearray()
        deadline = time.monotonic() + 10
        while process.poll() is None:
            if time.monotonic() > deadline:
                process.kill()
                raise AssertionError("spinner request did not finish")
            if select.select([master], [], [], 0.1)[0]:
                try:
                    chunk = os.read(master, 4096)
                except OSError as error:
                    if error.errno != errno.EIO:
                        raise
                    continue
                if chunk:
                    terminal.extend(chunk)
        while select.select([master], [], [], 0)[0]:
            try:
                chunk = os.read(master, 4096)
                if not chunk:
                    break
                terminal.extend(chunk)
            except OSError as error:
                if error.errno != errno.EIO:
                    raise
                break
        stdout = process.stdout.read()
        os.close(master)
        assert process.returncode == expected_status, (process.returncode, terminal)
        assert stdout == expected_stdout, stdout
        assert b"ai-shell: waiting" in terminal, terminal
        assert terminal.endswith(b"\r\x1b[2K") or b"\r\x1b[2Kai-shell: " in terminal, terminal
        assert b"test_key_secret_123" not in terminal


run_case(
    '{"status":"completed","output":[{"content":[{"type":"output_text","text":"echo ok"}]}]}',
    0,
    b"echo ok\n",
)
run_case(
    '{"status":"incomplete","incomplete_details":{"reason":"max_output_tokens"},"output":[]}',
    8,
    b"",
)
print("PASS spinner shows and clears on success and failure")
