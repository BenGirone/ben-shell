# Ubuntu Bash AI Shell Command Rewriter

## Project specification and implementation brief

**Status:** Ready for implementation  
**Target platform:** Ubuntu with GNU Bash and Readline  
**Primary model:** `gpt-6-luna`  
**Reasoning effort:** `low`  
**API:** OpenAI Responses API  
**Default key binding:** `Alt+I`

## 1. Purpose

Build a small, dependable command-line tool that rewrites a natural-language request at an interactive Bash prompt into a Bash command.

The user types a request such as:

```text
find every log file larger than 100 megabytes modified this week
```

When the user presses `Alt+I`, the integration must:

1. Read the entire current GNU Readline buffer.
2. Send that text, plus limited shell context, to a local `ai-shell` CLI.
3. Ask the OpenAI Responses API for a Bash command.
4. Replace the current Readline buffer with the generated command.
5. Leave the command unexecuted so the user can inspect, edit, or discard it.

The core safety property is simple: **the tool may propose text, but it must never execute the generated command.**

## 2. User experience

### 2.1 Primary workflow

```text
$ show me the five biggest files under this directory
  [user presses Alt+I]
$ find . -type f -printf '%s\t%p\n' | sort -nr | head -n 5
```

The rewritten command remains at the prompt. Bash does not run it until the user explicitly presses `Enter`.

### 2.2 Success behavior

- Replace the complete Readline buffer only after a valid, completed API response is received.
- Move the cursor to the end of the replacement command.
- Preserve multiline output when the proposed Bash command legitimately requires it.
- Write no status text to standard output other than the generated command.
- Avoid adding Markdown fences, a leading `$`, commentary, or explanation.

### 2.3 Failure behavior

- Preserve the original Readline buffer exactly.
- Display one concise diagnostic on standard error.
- Return a nonzero exit status from the CLI.
- Never replace the buffer with an empty or partial response.
- Never execute the original request or generated output.

Representative messages:

```text
ai-shell: OpenAI API key not found
ai-shell: request timed out
ai-shell: API returned HTTP 429: rate limit exceeded
ai-shell: response incomplete: max_output_tokens
ai-shell: model returned no command
ai-shell: response contained a refusal instead of a command
```

## 3. Scope

### 3.1 In scope for version 1

- Ubuntu and Bash interactive shells.
- GNU Readline integration using Bash's `READLINE_LINE` and `READLINE_POINT` variables.
- `Alt+I` as the default binding.
- A standalone Bash CLI backed by `curl` and `jq`.
- OpenAI Responses API requests using `gpt-6-luna` with low reasoning effort.
- Environment-variable and file-based API key loading.
- Strict response-state handling, including incomplete, failed, refused, malformed, and empty responses.
- Configurable timeout and output-token budget.
- Opt-in diagnostic logging with secret and prompt redaction.
- Automated unit and integration tests that do not require a live API.
- An optional, explicitly selected live smoke test.
- Packaging suitable for source installation and later Debian packaging.

### 3.2 Out of scope for version 1

- Automatically executing generated commands.
- Shell-history submission or automatic history modification.
- A full-screen terminal user interface.
- Persistent conversation history or use of `previous_response_id`.
- OpenAI tool calls, hosted shell, web search, or function calling.
- Command execution in a sandbox.
- Guaranteed detection of every dangerous command.
- Native zsh support; the architecture must make it straightforward to add later.

## 4. Required file layout

The installed version must keep the API client separate from shell-specific integration.

```text
~/.local/bin/ai-shell
~/.config/ai-shell/bash-integration.bash
~/.config/ai-shell/config
~/.config/ai-shell/openai_api_key
```

Recommended source repository layout:

```text
ai-shell/
├── README.md
├── LICENSE
├── Makefile
├── bin/
│   └── ai-shell
├── integrations/
│   ├── bash-integration.bash
│   └── zsh-integration.zsh        # future, not required in v1
├── config/
│   └── config.example
├── install.sh
├── uninstall.sh
├── tests/
│   ├── test-cli.bats
│   ├── test-bash-integration.bats
│   ├── fixtures/
│   │   ├── completed.json
│   │   ├── completed-multiline.json
│   │   ├── incomplete-max-tokens.json
│   │   ├── failed.json
│   │   ├── refused.json
│   │   ├── empty-output.json
│   │   └── malformed.json
│   └── helpers/
│       └── fake-curl
└── packaging/
    └── debian/                    # optional after v1 is stable
```

### 4.1 `~/.local/bin/ai-shell`

Responsibilities:

- Validate arguments and dependencies.
- Load configuration and the API key.
- Construct the JSON payload with `jq --arg`; do not interpolate user content into a jq program.
- Call the Responses API with bounded connection and total timeouts.
- Validate HTTP and JSON response state.
- Extract text content safely.
- Emit only the proposed command to standard output on success.
- Emit diagnostics only to standard error on failure.

The CLI must not depend on Readline, mutate a prompt, or execute output. It should be usable independently:

```bash
ai-shell --cwd "$PWD" -- "list the ten largest files here"
```

The `--` delimiter is required before user text so a request beginning with `-` cannot be interpreted as an option.

### 4.2 `~/.config/ai-shell/bash-integration.bash`

Responsibilities:

- Define a small Readline callback.
- Capture `READLINE_LINE` before invoking the CLI.
- Do nothing when the buffer is empty or only whitespace.
- Invoke the CLI and capture its exit status and standard output.
- Replace `READLINE_LINE` only when the CLI succeeds and returns nonempty output.
- Set `READLINE_POINT` to the byte length of the new buffer.
- Bind the callback to `Alt+I` without changing unrelated user bindings.

Conceptual integration:

```bash
__ai_shell_rewrite() {
    local original command status
    original=$READLINE_LINE

    [[ $original =~ [^[:space:]] ]] || return 0

    command=$(ai-shell --cwd "$PWD" -- "$original")
    status=$?

    if (( status == 0 )) && [[ -n $command ]]; then
        READLINE_LINE=$command
        READLINE_POINT=${#READLINE_LINE}
    fi
}

bind -x '"\ei":__ai_shell_rewrite'
```

The implementation may improve terminal redraw or error presentation, but must preserve the replacement-on-success-only rule. Command substitution removes trailing newline characters; this is acceptable because generated commands should not require trailing blank lines.

### 4.3 `~/.config/ai-shell/config`

Use a deliberately small shell-style configuration file. It is sourced by `ai-shell`, so installation must create it as user-owned and non-world-writable. Document that it contains executable shell syntax and must not be copied from an untrusted source.

Recommended defaults:

```bash
AI_SHELL_MODEL=gpt-6-luna
AI_SHELL_REASONING_EFFORT=low
AI_SHELL_MAX_OUTPUT_TOKENS=2048
AI_SHELL_CONNECT_TIMEOUT_SECONDS=5
AI_SHELL_TIMEOUT_SECONDS=30
AI_SHELL_DEBUG=0
AI_SHELL_LOG_FILE=
```

`2048` is a pragmatic starting budget for this narrow, low-reasoning task, not a guarantee. It must be configurable because `max_output_tokens` includes visible output, reasoning tokens, and other generated tokens. If the response ends with `status: incomplete` and `incomplete_details.reason: max_output_tokens`, the CLI must report that explicitly and must not use any partial text. Users can then increase the value based on observed usage.

An optional later feature may retry once with a larger configured budget, but v1 should prefer predictable latency and cost over an invisible retry. If retrying is implemented, it must be opt-in, capped, logged, and covered by tests.

## 5. Command-line interface contract

### 5.1 Invocation

```text
ai-shell [OPTIONS] -- REQUEST
```

Required options:

```text
--cwd PATH       Working directory supplied as context; defaults to $PWD
--help           Show usage and exit successfully
--version        Show version and exit successfully
--debug          Enable diagnostics for this invocation
```

The CLI may accept the request as one argument in v1. If it later accepts standard input, it must require an explicit `--stdin` flag so interactive use cannot accidentally block waiting for input.

### 5.2 Exit codes

Use stable, documented exit codes:

| Code | Meaning |
|---:|---|
| 0 | Valid completed command emitted |
| 2 | Usage or configuration error |
| 3 | Missing or unreadable API key |
| 4 | Missing runtime dependency |
| 5 | Network, TLS, or timeout failure |
| 6 | Non-success HTTP status |
| 7 | Malformed or unexpected API response |
| 8 | Incomplete, failed, refused, or empty model response |

The Bash integration only needs to distinguish zero from nonzero, but stable categories make diagnostics and testing easier.

### 5.3 Output contract

On success:

- Standard output contains the command and nothing else.
- A final newline is allowed and expected.
- Standard error is empty unless debug logging is explicitly enabled.

On failure:

- Standard output is empty.
- Standard error contains a concise explanation.
- The process returns a nonzero exit code.

This contract is essential because the Bash integration treats standard output as code to place in the prompt.

## 6. Configuration and API key handling

### 6.1 Precedence

Load settings in this order, from highest to lowest precedence:

1. Explicit command-line options.
2. Environment variables.
3. `~/.config/ai-shell/config`.
4. Built-in defaults.

Load the API key separately:

1. Use a nonempty `OPENAI_API_KEY` environment variable when present.
2. Otherwise read the first line of `${XDG_CONFIG_HOME:-$HOME/.config}/ai-shell/openai_api_key`.
3. Otherwise fail with exit code `3` and setup guidance.

### 6.2 Key-file requirements

- Create the configuration directory with mode `0700`.
- Create the key file with mode `0600`.
- Refuse, or at minimum warn, if the key file is group- or world-readable.
- Strip one trailing line ending, but do not print or log the key.
- Reject an empty key.
- Do not pass the key in a process argument or URL.
- Send it only in the `Authorization: Bearer` request header.
- Do not store the key in the repository, example files, test fixtures, shell history, or logs.

Recommended setup:

```bash
install -d -m 700 "$HOME/.config/ai-shell"
printf '%s\n' 'YOUR_API_KEY' > "$HOME/.config/ai-shell/openai_api_key"
chmod 600 "$HOME/.config/ai-shell/openai_api_key"
```

The README should recommend entering the real key through a non-echoing prompt or editor to avoid placing it in shell history. The literal placeholder above is illustrative only.

## 7. OpenAI Responses API contract

### 7.1 Endpoint and headers

```text
POST https://api.openai.com/v1/responses
Authorization: Bearer <key>
Content-Type: application/json
```

Use `curl --silent --show-error` with explicit connection and overall timeouts. Capture the response body and HTTP status separately so an error body can be parsed without confusing it with a command.

### 7.2 Request payload

Construct the payload with `jq -n` and `--arg`. Never build JSON by concatenating quoted shell strings.

Required shape:

```json
{
  "model": "gpt-6-luna",
  "reasoning": {
    "effort": "low"
  },
  "instructions": "Convert the user request into an Ubuntu Bash command. Return only the command, with no Markdown, explanation, or leading dollar sign. Prefer standard Ubuntu utilities. Do not use sudo unless clearly necessary. Never claim to have executed the command.",
  "input": "Request: <user buffer>\nCurrent directory: <working directory>",
  "max_output_tokens": 2048,
  "store": false
}
```

Equivalent safe construction:

```bash
payload=$(
    jq -n \
        --arg model "$model" \
        --arg effort "$reasoning_effort" \
        --arg request "$request" \
        --arg cwd "$cwd" \
        --arg instructions "$instructions" \
        --argjson max_output_tokens "$max_output_tokens" \
        '{
            model: $model,
            reasoning: {effort: $effort},
            instructions: $instructions,
            input: ("Request: " + $request + "\nCurrent directory: " + $cwd),
            max_output_tokens: $max_output_tokens,
            store: false
        }'
)
```

Before using `--argjson`, validate that `AI_SHELL_MAX_OUTPUT_TOKENS` is an integer within a documented range. Apply similar validation to timeouts and enumerated values.

### 7.3 Context minimization

Send only what is necessary:

- The user's current Readline buffer.
- The current working directory.
- The stable command-generation instructions.

Do not send environment variables, previous commands, shell history, file contents, directory listings, usernames, hostnames, Git state, or process output by default. Future context features must be explicit opt-ins with clear privacy documentation.

### 7.4 Response validation state machine

The implementation must process results in this order:

1. **Transport:** If `curl` fails, return a network error and emit no command.
2. **HTTP:** If the status is outside `200..299`, parse a safe API error message when possible, return an HTTP error, and emit no command.
3. **JSON:** If the body is not valid JSON, return a malformed-response error.
4. **Top-level error:** If `.error` is present, report its code or message without dumping the full response.
5. **Status:** Require `.status == "completed"`.
6. **Incomplete:** If `.status == "incomplete"`, report `.incomplete_details.reason`, especially `max_output_tokens`; discard all partial output.
7. **Failed or cancelled:** Report the response status and available safe error details.
8. **Refusal:** Detect content items with `.type == "refusal"`; emit no command.
9. **Text extraction:** Concatenate all `.output[]?.content[]?` items whose type is `output_text`, in response order.
10. **Normalization:** Remove an accidental surrounding Markdown fence and one leading prompt marker only if this can be done unambiguously. Do not aggressively rewrite shell syntax.
11. **Nonempty check:** Reject output that is empty or whitespace-only.
12. **Size check:** Reject output larger than a documented local byte limit, such as 64 KiB.
13. **Success:** Print the command and return zero.

Recommended extraction filter:

```jq
[
  .output[]?.content[]?
  | select(.type == "output_text")
  | .text
]
| join("")
```

Do not rely exclusively on a convenience field such as `.output_text`, because raw REST responses expose structured output items and the implementation should deliberately validate their types.

### 7.5 Token-budget behavior

`max_output_tokens` is an upper bound covering visible output and reasoning tokens. A reasoning model can consume the budget before producing visible text. Therefore:

- The default must be configurable.
- An incomplete response must never be treated as success, even if it includes partial output.
- `incomplete_details.reason` must appear in the diagnostic.
- Debug logs should record total output tokens and reasoning-token counts when present, but not model-generated reasoning content.
- Documentation should suggest increasing `AI_SHELL_MAX_OUTPUT_TOKENS` when the reason is `max_output_tokens`.
- Tests must include an incomplete response with no visible text and one with partial visible text; both must fail without emitting standard output.

## 8. Safety and security requirements

### 8.1 Execution boundary

The CLI and integration must not call `eval`, `bash -c`, `source`, `exec`, or an equivalent execution mechanism on generated output. They must not synthesize an `Enter` keypress. Assignment to `READLINE_LINE` is allowed; execution is not.

### 8.2 User review

Generated commands are untrusted suggestions. The README and installation message must tell users to inspect commands before running them, especially commands involving:

- `rm`, `dd`, `mkfs`, redirection, or recursive permission changes.
- `sudo` or privilege changes.
- Package installation or removal.
- Network downloads piped into a shell.
- Credential files, SSH material, cloud configuration, or secrets.
- Broad globs, filesystem roots, or command substitutions.
- Remote systems or production resources.

An optional warning layer may detect obvious high-risk patterns and print a warning while still leaving the command unexecuted. It must not be marketed as a security boundary; shell syntax is too flexible for a simple pattern matcher to prove safety.

### 8.3 Prompt injection and data exposure

Treat the Readline buffer and working-directory value as untrusted data. Delimit them clearly in the model input and keep the stable instructions separate in the `instructions` field. The model may still follow malicious text embedded in a request, so the final defense is visible user review and non-execution.

Never automatically read files named by the user or model. Never attach file contents to the API request in v1.

### 8.4 Shell and filesystem hygiene

- Quote every variable expansion unless intentional word splitting is explicitly required.
- Use `set -o nounset` and `set -o pipefail`; use `errexit` only where its edge cases are understood and tested.
- Use `mktemp` for temporary files and remove them with a trap.
- Avoid temporary files where variables can safely hold the response.
- Never place secrets in temporary files.
- Do not follow unsafe symlinks when creating configuration or log files.
- Validate configuration values before using them as `curl` options or `jq` data.
- Pin executable paths only if packaging requires it; otherwise check dependencies with `command -v`.

### 8.5 API behavior

- Set `store: false` in requests for this stateless local workflow.
- Do not enable model tools.
- Do not use multi-turn state.
- Do not send a stable user identifier by default.
- Honor proxy and CA settings through standard `curl` behavior unless security requirements later dictate otherwise.

## 9. Installation and removal

### 9.1 Prerequisites

- Ubuntu with interactive Bash and GNU Readline.
- `curl`.
- `jq`.
- An OpenAI API key with access to `gpt-6-luna`.

The installer should detect missing dependencies and print the exact Ubuntu package names without invoking `sudo` automatically.

### 9.2 Installer behavior

`install.sh` must:

1. Fail clearly on unsupported shells or missing source files.
2. Create `~/.local/bin` and the configuration directory if needed.
3. Install the CLI with mode `0755`.
4. Install the Bash integration with mode `0644`.
5. Install `config.example` as `config` only when no user config exists.
6. Never overwrite an existing API key.
7. Add one idempotent source line to `~/.bashrc`, or print the line for manual installation.
8. Avoid duplicate source lines on repeated runs.
9. Print the final key setup and reload instructions.

Recommended `.bashrc` line:

```bash
[[ -r "$HOME/.config/ai-shell/bash-integration.bash" ]] && \
    source "$HOME/.config/ai-shell/bash-integration.bash"
```

Apply changes with:

```bash
source "$HOME/.bashrc"
```

### 9.3 Uninstaller behavior

`uninstall.sh` must remove only files installed by this project and the exact managed `.bashrc` line. It must preserve by default:

- The API key.
- User-edited configuration.
- Logs.

Offer explicit flags to remove user data. Never recursively delete a broad directory without confirming that the resolved path is the exact project directory.

## 10. Logging and debugging

Logging is disabled by default.

### 10.1 Debug output

When `--debug` or `AI_SHELL_DEBUG=1` is set, diagnostics may include:

- Timestamp.
- CLI version.
- Model and reasoning effort.
- Configured timeouts and token budget.
- Request duration.
- HTTP status.
- Response status and incomplete reason.
- Response ID.
- Token usage totals and reasoning-token count when available.
- Final exit category.

Debug output must not include:

- The API key or Authorization header.
- Full request headers.
- The full user prompt by default.
- The generated command by default.
- Raw response bodies by default.
- Hidden reasoning content.
- Environment-variable dumps.

An explicit `AI_SHELL_DEBUG_CONTENT=1` may later log prompts and generated commands for local troubleshooting, but it must display a privacy warning, use a user-only log file, and still redact credentials.

### 10.2 Log destination

- Default debug destination: standard error.
- Optional file: `AI_SHELL_LOG_FILE`.
- Create log files with mode `0600`.
- Use append-only writes and a documented size or rotation strategy before enabling persistent logs by default.
- If the configured log path cannot be opened safely, warn and continue with standard error rather than failing a command rewrite.

## 11. Testing strategy

Use Bats Core or an equivalent Bash-focused test framework. Tests must be deterministic and must not require a real API key unless explicitly marked as live.

### 11.1 CLI unit and contract tests

Cover at least:

- Empty request and whitespace-only request.
- A request beginning with `-` after the `--` delimiter.
- Spaces, quotes, backslashes, dollar signs, command substitutions, Unicode, tabs, and embedded newlines in the request.
- A working directory containing spaces and Unicode.
- Missing `curl` and missing `jq`.
- Key precedence: environment over file.
- Missing, empty, unreadable, and overly permissive key files.
- Invalid model, effort, token, and timeout configuration values.
- Correct JSON encoding without injection or jq syntax errors.
- Successful single-line and multiline outputs.
- Multiple `output_text` blocks concatenated in order.
- HTTP 400, 401, 403, 429, and 500 responses.
- Network failure, TLS failure, connection timeout, and overall timeout.
- Malformed JSON and unexpected schemas.
- `completed` with empty output.
- `incomplete` because of `max_output_tokens`, with and without partial text.
- `failed`, `cancelled`, and refusal content.
- No command on stdout for every failure path.
- Stable exit codes and useful standard-error messages.
- No API key leakage in output or logs.

Use a fake `curl` executable placed first on `PATH`, or provide an internal transport override used only by tests. Fixture files should contain representative Responses API bodies.

### 11.2 Bash integration tests

Cover at least:

- Empty buffer does not invoke the CLI.
- CLI success replaces the buffer and moves the cursor to the end.
- CLI failure preserves the exact original buffer.
- Successful empty output is still rejected defensively.
- Multiline input and output remain intact.
- Existing unrelated Readline bindings are unchanged.
- Sourcing the integration more than once is harmless.
- An absent `ai-shell` executable produces a concise error without damaging the prompt.

Because `READLINE_LINE` is normally available only in a `bind -x` callback, keep the transformation logic in a small function that can be tested with controlled variables. Add a pseudo-terminal integration test if practical.

### 11.3 Static checks

- Run `shellcheck` on every shell file.
- Format consistently with `shfmt` if the project adopts it.
- Scan the repository for accidental API keys or Authorization headers.
- Verify installer idempotence in a temporary home directory.

### 11.4 Live smoke test

Provide an opt-in test such as:

```bash
AI_SHELL_LIVE_TEST=1 bats tests/live.bats
```

It must skip by default, require an externally supplied `OPENAI_API_KEY`, use one inexpensive request, never print the key, and assert that the result is nonempty without executing it.

## 12. Packaging and release

### 12.1 Initial distribution

The first release may be a source archive with:

- Versioned Git tags.
- Checksums.
- `install.sh` and `uninstall.sh`.
- A changelog.
- An MIT or similarly permissive license chosen by the maintainer.
- Reproducible tests in continuous integration on supported Ubuntu versions.

Do not recommend `curl | bash` as the primary installation path. Prefer downloading a tagged archive, verifying its checksum, inspecting it, and running the local installer.

### 12.2 Debian package

After the interface stabilizes, add a `.deb` that installs system-wide files under conventional locations, for example:

```text
/usr/bin/ai-shell
/usr/share/ai-shell/bash-integration.bash
/usr/share/doc/ai-shell/
```

System packaging must not create a per-user API key or silently modify every user's shell startup files. Provide documented per-user activation instead.

### 12.3 Versioning

Use semantic versioning. Treat changes to CLI arguments, exit codes, configuration names, output normalization, or shell-integration behavior as public-interface changes.

## 13. Extensibility and future zsh support

Keep the transport and response parser entirely in the standalone `ai-shell` executable. Shell integrations should be thin adapters with this shared contract:

```text
current editable buffer -> ai-shell -> replacement buffer
```

For future zsh support, add a ZLE widget that reads and writes `BUFFER` and sets `CURSOR`, while invoking the same CLI:

```zsh
function ai-shell-rewrite-widget() {
  local original=$BUFFER
  local replacement

  replacement=$(ai-shell --cwd "$PWD" -- "$original") || return
  [[ -n $replacement ]] || return

  BUFFER=$replacement
  CURSOR=${#BUFFER}
}

zle -N ai-shell-rewrite-widget
bindkey '^[i' ai-shell-rewrite-widget
```

This is illustrative, not part of the v1 acceptance criteria. Before shipping zsh support, test Meta-key behavior across common terminal emulators and account for zsh character indexing, widget redraw, and multiline buffers.

Other future extensions may include:

- Configurable key bindings.
- Additional model profiles.
- A local-only command-risk warning plugin.
- Optional context providers with explicit consent.
- Fish shell integration.
- Distribution packages for Debian, Homebrew, or other systems.

None of these should weaken the no-automatic-execution rule.

## 14. Acceptance criteria for version 1

Version 1 is complete when all of the following are true:

- On supported Ubuntu systems, pressing `Alt+I` converts a nonempty Bash Readline buffer into a proposed Bash command.
- The generated command replaces the buffer but is not executed.
- API requests use `gpt-6-luna`, `reasoning.effort: low`, the Responses API, and `store: false` by default.
- JSON construction safely preserves arbitrary user text and paths.
- Missing keys, missing dependencies, timeouts, HTTP errors, invalid JSON, refusals, failures, incomplete responses, and empty text all preserve the original buffer.
- Incomplete responses caused by `max_output_tokens` produce a specific diagnostic.
- Partial output from any incomplete response is discarded.
- The API key never appears in normal or debug output.
- The installer is idempotent and does not overwrite user secrets or configuration.
- Unit tests use mocked transport and cover every response state.
- `shellcheck` passes.
- A clean install, reload, rewrite, failure, and uninstall workflow is documented and manually verified.

## 15. Prioritized implementation roadmap

### Priority 0: Safety and executable core

1. Define CLI arguments, configuration names, exit codes, and output contract.
2. Implement API-key loading with secure permissions and precedence.
3. Implement safe JSON construction with `jq --arg` and numeric validation.
4. Implement bounded `curl` transport with separate body and HTTP-status capture.
5. Implement the response-validation state machine.
6. Guarantee no generated output is executed and no failure emits stdout.
7. Add fixtures and tests for success, incomplete, empty, refusal, HTTP, and malformed responses.

**Milestone:** `ai-shell --cwd "$PWD" -- "show hidden files"` reliably prints a command or a precise error.

### Priority 1: Bash interaction

1. Implement the Readline callback.
2. Bind `Alt+I`.
3. Preserve the original buffer on every failure path.
4. Support spaces, quotes, Unicode, and multiline buffers.
5. Test repeated sourcing and missing CLI behavior.

**Milestone:** The complete interactive workflow works without automatic execution.

### Priority 2: Installation and operator experience

1. Add the example configuration and secure key setup flow.
2. Build idempotent install and uninstall scripts.
3. Add dependency checks and clear setup diagnostics.
4. Write the README, security notice, troubleshooting guide, and examples.
5. Add opt-in debug logging with mandatory redaction.

**Milestone:** A new Ubuntu user can install, configure, use, diagnose, and remove the tool safely.

### Priority 3: Quality and release automation

1. Add `shellcheck`, formatting checks, secret scanning, and tests to CI.
2. Test against supported Ubuntu and Bash versions.
3. Add version metadata, changelog, license, release archive, and checksums.
4. Add an opt-in live API smoke test.

**Milestone:** A tagged source release is reproducible and testable.

### Priority 4: Extensions

1. Evaluate configurable bindings and optional capped retries.
2. Add zsh integration using the unchanged CLI contract.
3. Consider a Debian package.
4. Evaluate opt-in context and risk-warning plugins.

**Milestone:** New shells and features can be added without coupling them to the OpenAI transport layer.

## 16. Implementation notes for the coding agent

- Implement the smallest auditable design that satisfies the acceptance criteria.
- Prefer readable Bash over clever pipelines.
- Keep model output off stdout until every validation step has passed. Holding the candidate text in a variable prevents accidental partial success.
- Avoid piping `curl` directly into the final extraction command because transport failures, HTTP errors, and malformed bodies need distinct handling.
- Preserve API error bodies only long enough to extract safe diagnostics; do not dump them by default.
- Treat all configuration, request text, paths, network responses, and model output as untrusted input.
- Add tests before adding normalization heuristics. A false cleanup can silently change the meaning of a shell command.
- Document any intentional deviation from this specification in the repository's design notes.

## 17. Official API references

- [GPT-6 Luna model reference](https://developers.openai.com/api/docs/models/gpt-6-luna)
- [Responses API create reference](https://developers.openai.com/api/reference/cli/resources/responses/methods/create)
- [Reasoning models and incomplete response handling](https://developers.openai.com/api/docs/guides/reasoning)

These references establish that `gpt-6-luna` supports the Responses API and low reasoning effort, and that `max_output_tokens` includes both visible output and reasoning tokens. The API documentation also describes `status: incomplete` with `incomplete_details.reason: max_output_tokens`, including the case where no visible output is produced.
