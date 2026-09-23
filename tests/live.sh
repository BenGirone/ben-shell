#!/usr/bin/env bash
set -o nounset
set -o pipefail
set -e
[[ ${AI_SHELL_LIVE_TEST-0} == 1 ]] || { printf 'SKIP: set AI_SHELL_LIVE_TEST=1 to run\n'; exit 0; }
[[ -n ${OPENAI_API_KEY-} ]] || { printf 'SKIP: set OPENAI_API_KEY externally\n'; exit 0; }
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
result=$("$root/bin/ai-shell" -- 'print the current directory')
[[ -n $result ]]
printf 'PASS: received a nonempty proposed command\n'
