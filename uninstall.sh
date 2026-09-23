#!/usr/bin/env bash
set -o nounset
set -o pipefail
set -e
remove_user_data=0
case ${1-} in
    '') ;;
    --remove-user-data) remove_user_data=1 ;;
    *) printf 'Usage: uninstall.sh [--remove-user-data]\n' >&2; exit 2 ;;
esac
config_dir=${XDG_CONFIG_HOME:-$HOME/.config}/ai-shell
bin_dir=$HOME/.local/bin
rm -f -- "$bin_dir/ai-shell" "$config_dir/bash-integration.bash" "$config_dir/zsh-integration.zsh"
if [[ $config_dir == "$HOME/.config/ai-shell" ]]; then
    for rcfile in "$HOME/.bashrc" "$HOME/.zshrc"; do
        [[ -f $rcfile && ! -L $rcfile ]] || continue
        temp=$(mktemp) || exit 2
        # Match exactly the literal lines written by the installers.
        # shellcheck disable=SC2016
        grep -Fvx -e '[[ -r "$HOME/.config/ai-shell/bash-integration.bash" ]] && source "$HOME/.config/ai-shell/bash-integration.bash"' -e '[[ -r "$HOME/.config/ai-shell/zsh-integration.zsh" ]] && source "$HOME/.config/ai-shell/zsh-integration.zsh"' -e 'export PATH="$HOME/.local/bin:$PATH" # ai-shell' "$rcfile" > "$temp" || true
        cat -- "$temp" > "$rcfile"
        rm -f -- "$temp"
    done
fi
if ((remove_user_data)); then
    rm -f -- "$config_dir/config" "$config_dir/openai_api_key"
    if [[ -d $config_dir && ! -L $config_dir ]]; then
        rmdir -- "$config_dir" 2>/dev/null || true
    fi
fi
printf 'ai-shell removed. User configuration and key %s.\n' "$([[ $remove_user_data == 1 ]] && printf removed || printf preserved)"
