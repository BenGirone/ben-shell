# ai-shell

`ai-shell` turns text at an interactive shell prompt into a proposed command. It leaves the command in the editable prompt for review and **never executes it**.

While an interactive rewrite is waiting for the API, a spinner appears on the terminal. It clears before the proposed command or an error is shown.
Keys pressed during the wait are ignored, so press Enter only after the replacement is visible and reviewed.

| Platform | Shell | Key binding | Installer |
| --- | --- | --- | --- |
| Ubuntu | Bash / GNU Readline | Alt+I | `./install.sh` |
| macOS | zsh / ZLE | Ctrl+G | `./install-macos.sh` |

macOS zsh's ZLE exposes the whole editable buffer through `BUFFER`. The widget replaces that buffer and moves the cursor to its end; pressing the key binding does not submit the line. Ctrl+G replaces zsh's default `send-break` binding. The previous Ctrl+X, Ctrl+I sequence also remains available.

## One-command install

Use the platform's terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/BenGirone/ben-shell/v1.3.1/install-online.sh | bash
```

The downloadable script contains the source installer and a checksum-checked archive of the files it installs. It detects macOS or Ubuntu, prompts for the OpenAI API key through the terminal without echoing it, saves it as a user-only file, and installs the matching shell binding. An existing key is preserved. Download and inspect the script first if you prefer to review it before running it:

```bash
curl -fsSLo install-online.sh https://raw.githubusercontent.com/BenGirone/ben-shell/v1.3.1/install-online.sh
less install-online.sh
bash install-online.sh
```

The online installer needs `curl` and `jq` already installed. If `jq` is missing, install it with `sudo apt install jq` on Ubuntu or `brew install jq` on macOS, then rerun the installer. macOS also requires Homebrew for that command. The installer does not invoke `sudo` itself.

## Local install

Inspect this source tree, then run `./install.sh` on Ubuntu or `./install-macos.sh` on macOS. Add `--prompt-key` to enter the key through a non-echoing terminal prompt. Without the flag, you may set `OPENAI_API_KEY` or create `~/.config/ai-shell/openai_api_key` with mode `0600` using an editor or non-echoing prompt. Avoid putting the real key in a shell command or history.

The installers copy the CLI to `~/.local/bin/ai-shell` and shell integration to `~/.config/ai-shell/`. They add a PATH line and one source line to `~/.bashrc` or `~/.zshrc` without duplicating them on repeated runs. Existing config and key files are preserved. Reload with `source ~/.bashrc` or `source ~/.zshrc`, or open a new terminal.

Type a natural-language request at the prompt and press the binding. Inspect the proposed command, then press Enter only if you choose to run it. You can also call the CLI directly:

```bash
ai-shell --cwd "$PWD" -- 'show the five biggest files here'
ai-shell --platform macos -- 'list files larger than 100 MB'
```

`--` is required before the request, including requests beginning with `-`. The CLI detects macOS automatically, or accepts `--platform ubuntu|macos`. `--help`, `--version`, `--debug`, and the terminal-only `--spinner` option are also available. Success prints only a command to stdout. Failure prints a diagnostic to stderr and never prints a command. Exit codes: 2 usage/config, 3 key, 4 dependency, 5 transport, 6 HTTP, 7 malformed response, 8 incomplete/failed/refused/empty model response.

## Configuration

Edit `~/.config/ai-shell/config`, or set these environment variables to override it:

| Setting | Default | Valid values |
| --- | --- | --- |
| `AI_SHELL_MODEL` | `gpt-6-luna` | `gpt-` model name |
| `AI_SHELL_REASONING_EFFORT` | `low` | `minimal`, `low`, `medium`, `high`, `xhigh`, `max`, `ultra` |
| `AI_SHELL_MAX_OUTPUT_TOKENS` | `2048` | integer 1–32768 |
| `AI_SHELL_CONNECT_TIMEOUT_SECONDS` | `5` | integer 1–60 |
| `AI_SHELL_TIMEOUT_SECONDS` | `30` | integer 1–300 |
| `AI_SHELL_DEBUG` | `0` | `0` or `1` |
| `AI_SHELL_LOG_FILE` | empty | optional private log path |

The connection timeout cannot exceed the total timeout. If you see `response incomplete: max_output_tokens`, increase the token budget. Incomplete responses are discarded, even if they contain partial command text. The config file is sourced as Bash code, so keep it user-owned and never copy it from an untrusted source.

`--debug` or `AI_SHELL_DEBUG=1` logs timing and response metadata, without the key, request, or generated command. Debug output goes to stderr unless `AI_SHELL_LOG_FILE` is set. A log file is created with mode `0600`; if unavailable, debug output falls back to stderr. Persistent logs are opt-in and are not rotated automatically.

## Safety

Generated commands are untrusted suggestions. Inspect commands involving deletion (`rm`, `dd`, `mkfs`), redirection, recursive permissions, `sudo`, package changes, downloads piped to a shell, credentials, broad globs, command substitution, remote hosts, or production systems. The model does not inspect your filesystem or execute the proposed command. It receives only the request text, current directory, and target platform; no history, file contents, environment, Git state, or prior conversation is sent. The API request uses `store: false`.

## Tests and removal

```bash
make check
./uninstall.sh
```

The default suite uses a fake `curl` and no real API key. On macOS it also tests the zsh widget. `make check` runs ShellCheck when installed. For one opt-in live API request, set `AI_SHELL_LIVE_TEST=1` and `OPENAI_API_KEY`, then run `bash tests/live.sh`. It executes no generated command.

`uninstall.sh` removes the installed executable, shell integration, and managed shell startup lines. It preserves the key, config, and logs. `./uninstall.sh --remove-user-data` additionally removes the key and config. It never deletes logs.
