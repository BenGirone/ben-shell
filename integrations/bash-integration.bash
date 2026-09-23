# Source this file from interactive Bash. The proposed command is never executed.
if [[ $- == *i* ]]; then
    __ai_shell_rewrite() {
        local original command_text status
        original=$READLINE_LINE
        [[ $original =~ [^[:space:]] ]] || return 0
        if ! type -P ai-shell >/dev/null 2>&1; then
            printf 'ai-shell: executable not found in PATH\n' >&2
            return 0
        fi
        if command_text=$(ai-shell --cwd "$PWD" -- "$original"); then
            status=0
        else
            status=$?
        fi
        if ((status == 0)) && [[ -n $command_text ]]; then
            READLINE_LINE=$command_text
            local LC_ALL=C
            READLINE_POINT=${#READLINE_LINE}
        fi
        return 0
    }
    bind -x '"\ei":__ai_shell_rewrite'
fi
