#!/usr/bin/env bash
set -o nounset
set -o pipefail
set -e
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home" "$tmp/config/ai-shell"
cp "$root/tests/helpers/fake-curl" "$tmp/bin/curl"
chmod +x "$tmp/bin/curl"
export PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin" HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config"
export OPENAI_API_KEY='test_key_secret_123' FAKE_EXPECT_KEY='test_key_secret_123' FAKE_PAYLOAD_COPY="$tmp/payload" FAKE_RESPONSE="$tmp/response"
unset AI_SHELL_MODEL AI_SHELL_REASONING_EFFORT AI_SHELL_MAX_OUTPUT_TOKENS AI_SHELL_CONNECT_TIMEOUT_SECONDS AI_SHELL_TIMEOUT_SECONDS AI_SHELL_DEBUG AI_SHELL_LOG_FILE
pass=0
run_case() {
    local expected=$1 name=$2
    shift 2
    local status=0
    "$root/bin/ai-shell" "$@" > "$tmp/stdout" 2> "$tmp/stderr" || status=$?
    if [[ $status != "$expected" ]]; then printf 'FAIL %s: expected exit %s, got %s: %s\n' "$name" "$expected" "$status" "$(cat "$tmp/stderr")" >&2; exit 1; fi
    if ((expected != 0)) && [[ -s $tmp/stdout ]]; then printf 'FAIL %s: failure emitted stdout\n' "$name" >&2; exit 1; fi
    if grep -q 'test_key_secret_123' "$tmp/stdout" "$tmp/stderr"; then printf 'FAIL %s: key leaked\n' "$name" >&2; exit 1; fi
    pass=$((pass+1))
}
response() { printf '%s' "$1" > "$FAKE_RESPONSE"; }
response '{"status":"completed","output":[{"content":[{"type":"output_text","text":"echo one"},{"type":"output_text","text":" && echo two"}]}]}'
run_case 0 success --cwd "$tmp/home" -- 'show one and two'
[[ $(cat "$tmp/stdout") == 'echo one && echo two' ]]
run_case 0 spinner-without-terminal --spinner -- 'show one and two'
[[ ! -s $tmp/stderr ]]
jq -e '.model == "gpt-6-luna" and .reasoning.effort == "low" and .store == false' "$tmp/payload" >/dev/null
request=$'-starts "quoted" \\ $HOME $(id) ☃\nnext\tline'
run_case 0 encoding --cwd "$tmp/home" -- "$request"
jq -e --arg expected "$request" '.input | contains($expected)' "$tmp/payload" >/dev/null
run_case 0 explicit-macos --platform macos -- 'find big files'
jq -e '.input | contains("Platform: macos")' "$tmp/payload" >/dev/null
jq -e '.instructions | contains("macOS zsh")' "$tmp/payload" >/dev/null
run_case 2 bad-platform --platform solaris -- 'x'
response '{"status":"completed","output":[{"content":[{"type":"output_text","text":"echo first\necho second"}]}]}'
run_case 0 multiline -- "$request"
[[ $(cat "$tmp/stdout") == $'echo first\necho second' ]]
# shellcheck disable=SC2016 # Literal backticks in fixture JSON.
response '{"status":"completed","output":[{"content":[{"type":"output_text","text":"```bash\necho fenced\n```"}]}]}'
run_case 0 fenced -- 'x'
[[ $(cat "$tmp/stdout") == 'echo fenced' ]]
response '{"status":"completed","output":[{"content":[{"type":"output_text","text":"$ echo prompted"}]}]}'
run_case 0 prompt-marker -- 'x'
[[ $(cat "$tmp/stdout") == 'echo prompted' ]]
response '{"status":"incomplete","incomplete_details":{"reason":"max_output_tokens"},"output":[{"content":[{"type":"output_text","text":"partial"}]}]}'
run_case 8 incomplete-partial -- 'x'
grep -q 'max_output_tokens' "$tmp/stderr"
response '{"status":"incomplete","incomplete_details":{"reason":"max_output_tokens"},"output":[]}'
run_case 8 incomplete-empty -- 'x'
response '{"status":"failed","error":null,"output":[]}'
run_case 8 failed -- 'x'
response '{"status":"cancelled","output":[]}'
run_case 8 cancelled -- 'x'
response '{"status":"completed","output":[{"content":[{"type":"refusal","refusal":"no"}]}]}'
run_case 8 refusal -- 'x'
response '{"status":"completed","output":[{"content":[{"type":"output_text","text":"  "}]}]}'
run_case 8 empty -- 'x'
response 'bad json'
run_case 7 malformed -- 'x'
response '{"status":"completed","error":{},"output":[]}'
run_case 7 top-level-error -- 'x'
response '{"status":"completed","output":"wrong"}'
run_case 7 schema -- 'x'
response '{"status":"completed","output":[{"content":[{"type":"output_text","text":"echo\u0000bad"}]}]}'
run_case 7 nul-output -- 'x'
response '{"error":{"message":"rate limit exceeded"}}'
for code in 400 401 403 429 500; do FAKE_HTTP_STATUS=$code run_case 6 "http-$code" -- 'x'; done
FAKE_CURL_EXIT=28 run_case 5 timeout -- 'x'
FAKE_CURL_EXIT=60 run_case 5 tls -- 'x'
run_case 2 empty-request -- '  '
AI_SHELL_MODEL='wrong' run_case 2 bad-model -- 'x'
AI_SHELL_REASONING_EFFORT='wrong' run_case 2 bad-effort -- 'x'
AI_SHELL_MAX_OUTPUT_TOKENS='x' run_case 2 bad-tokens -- 'x'
AI_SHELL_TIMEOUT_SECONDS='0' run_case 2 bad-timeout -- 'x'
unset OPENAI_API_KEY
run_case 3 missing-key -- 'x'
printf 'file_key\n' > "$tmp/config/ai-shell/openai_api_key"
chmod 644 "$tmp/config/ai-shell/openai_api_key"
run_case 3 permissive-key -- 'x'
chmod 600 "$tmp/config/ai-shell/openai_api_key"
response '{"status":"completed","output":[{"content":[{"type":"output_text","text":"echo ok"}]}]}'
FAKE_EXPECT_KEY=file_key run_case 0 file-key -- 'x'
export OPENAI_API_KEY='test_key_secret_123'
FAKE_EXPECT_KEY=test_key_secret_123 run_case 0 env-key-precedence -- 'x'
printf 'AI_SHELL_MAX_OUTPUT_TOKENS=1234\n' > "$tmp/config/ai-shell/config"
chmod 600 "$tmp/config/ai-shell/config"
run_case 0 config-value -- 'x'
jq -e '.max_output_tokens == 1234' "$tmp/payload" >/dev/null
AI_SHELL_MAX_OUTPUT_TOKENS=5678 run_case 0 env-config-precedence -- 'x'
jq -e '.max_output_tokens == 5678' "$tmp/payload" >/dev/null
rm "$tmp/config/ai-shell/config"
export OPENAI_API_KEY='test_key_secret_123'

# Exercise the transformation function without a live Readline prompt.
source_text=$(sed 's/^if \[\[ \$- == \*i\* \]\]; then/if true; then/' "$root/integrations/bash-integration.bash")
bind() { :; }
eval "$source_text"
READLINE_LINE='original'; READLINE_POINT=2
__ai_shell_rewrite
[[ $READLINE_LINE == original && $READLINE_POINT == 2 ]] # type -P guards missing executable
cp "$root/bin/ai-shell" "$tmp/bin/ai-shell"
chmod +x "$tmp/bin/ai-shell"
response '{"status":"completed","output":[{"content":[{"type":"output_text","text":"echo replacement"}]}]}'
READLINE_LINE='original'; READLINE_POINT=2
__ai_shell_rewrite
[[ $READLINE_LINE == 'echo replacement' && $READLINE_POINT == 16 ]]
READLINE_LINE='  '; READLINE_POINT=1
__ai_shell_rewrite
[[ $READLINE_LINE == '  ' && $READLINE_POINT == 1 ]]
response '{"status":"completed","output":[{"content":[{"type":"output_text","text":"echo ☃"}]}]}'
READLINE_LINE='snowman'; READLINE_POINT=0
__ai_shell_rewrite
[[ $READLINE_LINE == 'echo ☃' && $READLINE_POINT == 8 ]]
# A failed rewrite must preserve the exact input and cursor.
response '{"status":"incomplete","incomplete_details":{"reason":"max_output_tokens"},"output":[]}'
READLINE_LINE=$'original\nsecond'; READLINE_POINT=3
if __ai_shell_rewrite 2> "$tmp/integration-stderr"; then :; fi
[[ $READLINE_LINE == $'original\nsecond' && $READLINE_POINT == 3 ]]

# Install twice, then remove only managed files and preserve user data.
HOME="$tmp/home" XDG_CONFIG_HOME='' "$root/install.sh" > "$tmp/install-1"
HOME="$tmp/home" XDG_CONFIG_HOME='' "$root/install.sh" > "$tmp/install-2"
# shellcheck disable=SC2016 # Match the literal managed .bashrc line.
[[ $(grep -Fc 'source "$HOME/.config/ai-shell/bash-integration.bash"' "$tmp/home/.bashrc") == 1 ]]
[[ -f $tmp/home/.config/ai-shell/config ]]
HOME="$tmp/home" XDG_CONFIG_HOME='' "$root/uninstall.sh" > "$tmp/uninstall"
[[ ! -e $tmp/home/.local/bin/ai-shell && -f $tmp/home/.config/ai-shell/config ]]
printf 'PASS %s CLI cases and Bash callback checks\n' "$pass"
