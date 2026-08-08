#!/usr/bin/env bash
# Resume the most recent Claude Code session after a usage-limit reset.

set -u

readonly RESUME_PROMPT="Review the project state and continue from where the session stopped."
readonly RETRY_SECONDS="${CLAUDE_SMART_RETRY_SECONDS:-900}"
readonly MAX_RETRIES="${CLAUDE_SMART_MAX_RETRIES:-24}"

usage() {
    cat <<'EOF'
Usage: claude-smart

Continues the most recent Claude Code session in the current directory. If
Claude exits after reporting a usage limit, the command waits and retries.

Environment variables:
  CLAUDE_SMART_RETRY_SECONDS  Seconds between retries (default: 900)
  CLAUDE_SMART_MAX_RETRIES    Maximum retries; 0 means unlimited (default: 24)
EOF
}

if [[ ${1:-} == "--help" || ${1:-} == "-h" ]]; then
    usage
    exit 0
elif [[ $# -ne 0 ]]; then
    usage >&2
    exit 64
fi

if [[ ! $RETRY_SECONDS =~ ^[1-9][0-9]*$ ]]; then
    echo "claude-smart: CLAUDE_SMART_RETRY_SECONDS must be a positive integer" >&2
    exit 64
fi

if [[ ! $MAX_RETRIES =~ ^[0-9]+$ ]]; then
    echo "claude-smart: CLAUDE_SMART_MAX_RETRIES must be a non-negative integer" >&2
    exit 64
fi

if ! command -v claude >/dev/null 2>&1; then
    echo "claude-smart: claude is not installed or is not on PATH" >&2
    exit 127
fi

if ! command -v script >/dev/null 2>&1; then
    echo "claude-smart: the script utility is required to preserve the interactive terminal" >&2
    exit 127
fi

if [[ ! -t 0 || ! -t 1 ]]; then
    echo "claude-smart: run this command from an interactive terminal" >&2
    exit 64
fi

log_file=$(mktemp "${TMPDIR:-/tmp}/claude-smart.XXXXXX") || exit 1
cleanup() {
    rm -f "$log_file"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM

run_claude() {
    : > "$log_file"

    if [[ $(uname -s) == "Darwin" ]]; then
        script -q -e "$log_file" claude --continue "$RESUME_PROMPT"
    else
        CLAUDE_SMART_RESUME_PROMPT=$RESUME_PROMPT \
            script -q -e -c 'exec claude --continue "$CLAUDE_SMART_RESUME_PROMPT"' "$log_file"
    fi
}

limit_was_reached() {
    LC_ALL=C grep -aiEq \
        "(usage|rate|session)[[:space:]-]+limit.{0,40}(reached|exceeded)|you.?ve hit your.{0,20}limit|quota exceeded|limit.{0,40}resets at" \
        "$log_file"
}

retry_count=0

echo "Starting Claude Code auto-resume wrapper."

while true; do
    echo "Launching or resuming the most recent Claude Code session..."

    run_claude
    claude_exit=$?

    if limit_was_reached; then
        retry_count=$((retry_count + 1))

        if (( MAX_RETRIES > 0 && retry_count > MAX_RETRIES )); then
            echo "Claude Code still reports a usage limit after $MAX_RETRIES retries; stopping." >&2
            exit 75
        fi

        echo "Claude Code reported a usage limit. Retrying in $RETRY_SECONDS seconds."
        sleep "$RETRY_SECONDS"
        continue
    fi

    if (( claude_exit == 0 )); then
        echo "Claude Code exited normally."
        exit 0
    fi

    echo "Claude Code exited with status $claude_exit and no usage-limit message; stopping." >&2
    exit "$claude_exit"
done
