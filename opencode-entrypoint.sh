#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "--bash" ]]; then
    shift
    # Full job control, normal shell
    exec bash "$@"
fi

# Default: OpenCode mode (no Ctrl-Z)
trap '' SIGTSTP SIGTTIN SIGTTOU
exec opencode "$@"
