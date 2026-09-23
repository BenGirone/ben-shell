# Source from the local installers when --prompt-key is requested.
ai_shell_prompt_key() {
    local key_file=$1 key
    if [[ -e $key_file || -L $key_file ]]; then
        [[ -f $key_file && ! -L $key_file ]] || { printf 'ai-shell: existing key path is unsafe\n' >&2; return 3; }
        printf 'ai-shell: existing API key preserved\n'
        return 0
    fi
    [[ -r /dev/tty ]] || { printf 'ai-shell: a terminal is required to enter the API key\n' >&2; return 3; }
    IFS= read -r -s -p 'OpenAI API key: ' key < /dev/tty || return 3
    printf '\n' > /dev/tty
    [[ $key =~ ^[a-zA-Z0-9._-]+$ ]] || { printf 'ai-shell: key is empty or contains unsupported characters\n' >&2; return 3; }
    (umask 077; set -o noclobber; printf '%s\n' "$key" > "$key_file") || { printf 'ai-shell: could not create API key file\n' >&2; return 3; }
    chmod 600 "$key_file"
    unset key
    printf 'ai-shell: API key saved with mode 0600\n'
}
