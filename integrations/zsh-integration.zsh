# Source from interactive zsh. Ctrl+G rewrites the current ZLE buffer.
[[ -o interactive ]] || return 0

function ai-shell-rewrite-widget() {
    emulate -L zsh
    local original=$BUFFER
    local replacement
    [[ -n ${original//[[:space:]]/} ]] || return 0
    if (( ! $+commands[ai-shell] )); then
        print -u2 -- 'ai-shell: executable not found in PATH'
        zle -M 'ai-shell: executable not found in PATH'
        return 0
    fi
    # External terminal output from the spinner invalidates ZLE's cached prompt.
    zle -I
    local cli_status=0 ignored pending_count=0
    replacement=$(command ai-shell --spinner --platform macos --cwd "$PWD" -- "$original") || cli_status=$?
    # Keys typed during the request, especially Enter, must not act on the new buffer.
    while (( (PENDING > 0 || KEYS_QUEUED_COUNT > 0) && pending_count < 4096 )); do
        read -k 1 -t 0 ignored || break
        (( ++pending_count ))
    done
    if (( cli_status == 0 )); then
        if [[ -n $replacement ]]; then
            BUFFER=$replacement
            CURSOR=${#BUFFER}
        fi
    fi
    zle -R
    return 0
}

zle -N ai-shell-rewrite-widget
bindkey '^G' ai-shell-rewrite-widget
# Keep the previous binding for existing users.
bindkey '^X^I' ai-shell-rewrite-widget
