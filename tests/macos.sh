#!/usr/bin/env bash
set -o nounset
set -o pipefail
set -e
[[ $(uname -s) == Darwin ]] || exit 0
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/home" "$tmp/fake-bin"
cp "$root/tests/helpers/fake-curl" "$tmp/fake-bin/curl"
chmod +x "$tmp/fake-bin/curl"
export HOME="$tmp/home" XDG_CONFIG_HOME='' PATH="$tmp/fake-bin:$PATH"
export OPENAI_API_KEY='test_key_secret_123' FAKE_EXPECT_KEY='test_key_secret_123'
export FAKE_PAYLOAD_COPY="$tmp/payload" FAKE_RESPONSE="$tmp/response"
"$root/install-macos.sh" > "$tmp/install-1"
"$root/install-macos.sh" > "$tmp/install-2"
export PATH="$HOME/.local/bin:$PATH"
# shellcheck disable=SC2016 # Match literal managed zsh startup lines.
[[ $(grep -Fc 'source "$HOME/.config/ai-shell/zsh-integration.zsh"' "$HOME/.zshrc") == 1 ]]
# shellcheck disable=SC2016
[[ $(grep -Fc 'export PATH="$HOME/.local/bin:$PATH" # ai-shell' "$HOME/.zshrc") == 1 ]]
printf '%s' '{"status":"completed","output":[{"content":[{"type":"output_text","text":"echo ☃"}]}]}' > "$FAKE_RESPONSE"
result=$(zsh -fic 'source "$HOME/.config/ai-shell/zsh-integration.zsh"; source "$HOME/.config/ai-shell/zsh-integration.zsh"; function zle() { :; }; BUFFER="find snow"; CURSOR=1; ai-shell-rewrite-widget; print -r -- "$BUFFER|$CURSOR"')
[[ $result == 'echo ☃|6' ]]
jq -e '.input | contains("Platform: macos")' "$tmp/payload" >/dev/null
printf '%s' '{"status":"incomplete","incomplete_details":{"reason":"max_output_tokens"},"output":[]}' > "$FAKE_RESPONSE"
result=$(zsh -fic 'source "$HOME/.config/ai-shell/zsh-integration.zsh"; function zle() { :; }; BUFFER="keep this"; CURSOR=2; ai-shell-rewrite-widget 2>/dev/null; print -r -- "$BUFFER|$CURSOR"')
[[ $result == 'keep this|2' ]]
binding=$(zsh -fic 'bindkey "^X^I"')
[[ $binding == *ai-shell-rewrite-widget* ]]
"$root/uninstall.sh" > "$tmp/uninstall"
[[ ! -e $HOME/.local/bin/ai-shell && ! -e $HOME/.config/ai-shell/zsh-integration.zsh ]]
[[ -f $HOME/.config/ai-shell/config ]]
printf 'PASS macOS zsh install, binding, rewrite, failure, and uninstall\n'
