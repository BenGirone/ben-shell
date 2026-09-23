#!/usr/bin/env bash
set -o nounset
set -o pipefail
set -e
prompt_key=0
case ${1-} in
    '') ;;
    --prompt-key) prompt_key=1 ;;
    *) printf 'Usage: install-macos.sh [--prompt-key]\n' >&2; exit 2 ;;
esac
[[ $(uname -s) == Darwin ]] || { printf 'ai-shell: macOS installer requires macOS\n' >&2; exit 2; }
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
for file in bin/ai-shell integrations/zsh-integration.zsh config/config.example scripts/prompt-key.bash; do
    [[ -f $root/$file ]] || { printf 'ai-shell: missing source file: %s\n' "$file" >&2; exit 2; }
done
missing=()
for dep in curl jq; do command -v "$dep" >/dev/null 2>&1 || missing+=("$dep"); done
if ((${#missing[@]})); then
    printf 'ai-shell: missing dependencies. Install with: brew install %s\n' "${missing[*]}" >&2
    exit 4
fi
config_dir=${XDG_CONFIG_HOME:-$HOME/.config}/ai-shell
bin_dir=$HOME/.local/bin
[[ ! -L $config_dir && ! -L $bin_dir ]] || { printf 'ai-shell: refusing symlinked install directory\n' >&2; exit 2; }
zshrc=$HOME/.zshrc
[[ ! -L $zshrc ]] || { printf 'ai-shell: refusing symlinked .zshrc\n' >&2; exit 2; }
install -d -m 700 -- "$config_dir"
install -d -m 755 -- "$bin_dir"
install -m 755 -- "$root/bin/ai-shell" "$bin_dir/ai-shell"
install -m 644 -- "$root/integrations/zsh-integration.zsh" "$config_dir/zsh-integration.zsh"
if [[ ! -e $config_dir/config && ! -L $config_dir/config ]]; then
    install -m 600 -- "$root/config/config.example" "$config_dir/config"
fi
# shellcheck disable=SC2016 # The literal HOME is evaluated when zsh reads .zshrc.
managed_line='[[ -r "$HOME/.config/ai-shell/zsh-integration.zsh" ]] && source "$HOME/.config/ai-shell/zsh-integration.zsh"'
# shellcheck disable=SC2016 # The literal HOME is evaluated when zsh reads .zshrc.
path_line='export PATH="$HOME/.local/bin:$PATH" # ai-shell'
if [[ $config_dir == "$HOME/.config/ai-shell" ]]; then
    touch -- "$zshrc"
    if ! grep -Fqx -- "$path_line" "$zshrc"; then printf '\n%s\n' "$path_line" >> "$zshrc"; fi
    if ! grep -Fqx -- "$managed_line" "$zshrc"; then printf '\n%s\n' "$managed_line" >> "$zshrc"; fi
else
    printf 'Add this to your .zshrc: source "%s/zsh-integration.zsh"\n' "$config_dir"
fi
if ((prompt_key)); then
    # shellcheck source=scripts/prompt-key.bash
    source "$root/scripts/prompt-key.bash"
    ai_shell_prompt_key "$config_dir/openai_api_key"
fi
cat <<EOF
Installed ai-shell for macOS zsh in $bin_dir.
Ensure $bin_dir is in PATH, then run: source ~/.zshrc
Type a request and press Ctrl+X Ctrl+I. Inspect the proposed command before pressing Enter.
EOF
