#!/usr/bin/env bash
set -o nounset
set -o pipefail
set -e
prompt_key=0
case ${1-} in
    '') ;;
    --prompt-key) prompt_key=1 ;;
    *) printf 'Usage: install.sh [--prompt-key]\n' >&2; exit 2 ;;
esac
[[ -n ${BASH_VERSION-} ]] || { printf 'ai-shell: run installer with Bash\n' >&2; exit 2; }
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
for file in bin/ai-shell integrations/bash-integration.bash config/config.example scripts/prompt-key.bash; do
    [[ -f $root/$file ]] || { printf 'ai-shell: missing source file: %s\n' "$file" >&2; exit 2; }
done
missing=()
for dep in curl jq; do command -v "$dep" >/dev/null 2>&1 || missing+=("$dep"); done
if ((${#missing[@]})); then
    printf 'ai-shell: missing dependencies. On Ubuntu install: sudo apt install %s\n' "${missing[*]}" >&2
    exit 4
fi
config_dir=${XDG_CONFIG_HOME:-$HOME/.config}/ai-shell
bin_dir=$HOME/.local/bin
[[ ! -L $config_dir && ! -L $bin_dir ]] || { printf 'ai-shell: refusing symlinked install directory\n' >&2; exit 2; }
install -d -m 700 -- "$config_dir"
install -d -m 755 -- "$bin_dir"
install -m 755 -- "$root/bin/ai-shell" "$bin_dir/ai-shell"
install -m 644 -- "$root/integrations/bash-integration.bash" "$config_dir/bash-integration.bash"
if [[ ! -e $config_dir/config && ! -L $config_dir/config ]]; then
    install -m 600 -- "$root/config/config.example" "$config_dir/config"
fi
bashrc=$HOME/.bashrc
# shellcheck disable=SC2016 # The literal HOME is evaluated when Bash reads .bashrc.
managed_line='[[ -r "$HOME/.config/ai-shell/bash-integration.bash" ]] && source "$HOME/.config/ai-shell/bash-integration.bash"'
# shellcheck disable=SC2016 # The literal HOME is evaluated when Bash reads .bashrc.
path_line='export PATH="$HOME/.local/bin:$PATH" # ai-shell'
if [[ $config_dir == "$HOME/.config/ai-shell" ]]; then
    [[ ! -L $bashrc ]] || { printf 'ai-shell: refusing symlinked .bashrc\n' >&2; exit 2; }
    touch -- "$bashrc"
    if ! grep -Fqx -- "$path_line" "$bashrc"; then printf '\n%s\n' "$path_line" >> "$bashrc"; fi
    if ! grep -Fqx -- "$managed_line" "$bashrc"; then
        printf '\n%s\n' "$managed_line" >> "$bashrc"
    fi
else
    printf 'Add this to your .bashrc: source "%s/bash-integration.bash"\n' "$config_dir"
fi
if ((prompt_key)); then
    # shellcheck source=scripts/prompt-key.bash
    source "$root/scripts/prompt-key.bash"
    ai_shell_prompt_key "$config_dir/openai_api_key"
fi
cat <<EOF
Installed ai-shell in $bin_dir.
If needed, enter your API key in $config_dir/openai_api_key with a non-echoing prompt or editor, then chmod 600 that file.
Ensure $bin_dir is in PATH, then run: source ~/.bashrc
Inspect every proposed command before pressing Enter. Generated commands are never executed automatically.
EOF
