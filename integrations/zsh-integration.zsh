# Source from interactive zsh. Ctrl+X Ctrl+I rewrites the current ZLE buffer.
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
    if replacement=$(command ai-shell --spinner --platform macos --cwd "$PWD" -- "$original"); then
        if [[ -n $replacement ]]; then
            BUFFER=$replacement
            CURSOR=${#BUFFER}
        fi
    fi
    zle -R
    return 0
}

zle -N ai-shell-rewrite-widget
bindkey '^X^I' ai-shell-rewrite-widget
