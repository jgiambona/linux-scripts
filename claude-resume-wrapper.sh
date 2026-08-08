#!/usr/bin/env bash
# Resume a Claude Code session after a usage-limit reset.

set -u

readonly RESUME_PROMPT="Review the project state and continue from where the session stopped."
readonly RETRY_SECONDS="${CLAUDE_SMART_RETRY_SECONDS:-900}"
readonly MAX_RETRIES="${CLAUDE_SMART_MAX_RETRIES:-24}"

usage() {
    cat <<'EOF'
Usage: claude-smart [CLAUDE_OPTIONS] [PROMPT]

Starts a fresh Claude Code session by default and passes interactive Claude
options through. If Claude exits after reporting a usage limit, the command
waits and resumes the same session.

Examples:
  claude-smart
  claude-smart --name billing-fix --model opus
  claude-smart --worktree billing-fix --model sonnet
  claude-smart --continue
  claude-smart --resume SESSION_ID

The wrapper does not support non-interactive, background, cloud, remote-control,
non-persistent, or forked sessions.

Environment variables:
  CLAUDE_SMART_RETRY_SECONDS  Seconds between retries (default: 900)
  CLAUDE_SMART_MAX_RETRIES    Maximum retries; 0 means unlimited (default: 24)
EOF
}

if [[ $# -eq 1 && ( $1 == "--help" || $1 == "-h" ) ]]; then
    usage
    exit 0
fi

if [[ ! $RETRY_SECONDS =~ ^[1-9][0-9]*$ ]]; then
    echo "claude-smart: CLAUDE_SMART_RETRY_SECONDS must be a positive integer" >&2
    exit 64
fi

if [[ ! $MAX_RETRIES =~ ^[0-9]+$ ]]; then
    echo "claude-smart: CLAUDE_SMART_MAX_RETRIES must be a non-negative integer" >&2
    exit 64
fi

original_args=("$@")
session_mode="fresh"
session_id=""
selector_count=0

set_session_selector() {
    session_mode=$1
    session_id=${2:-}
    selector_count=$((selector_count + 1))

    if (( selector_count > 1 )); then
        echo "claude-smart: use only one of --continue, --resume, or --session-id" >&2
        exit 64
    fi
}

for ((i = 0; i < ${#original_args[@]}; i++)); do
    argument=${original_args[i]}

    if [[ $argument == "--" ]]; then
        break
    fi

    case $argument in
        -c|--continue)
            set_session_selector "continue"
            ;;
        -r|--resume)
            resume_value=""
            if (( i + 1 < ${#original_args[@]} )) && [[ ${original_args[i + 1]} != -* ]]; then
                resume_value=${original_args[i + 1]}
            fi
            if [[ $resume_value =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
                set_session_selector "resume" "$resume_value"
            else
                set_session_selector "continue"
            fi
            ;;
        --resume=*)
            resume_value=${argument#*=}
            if [[ $resume_value =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
                set_session_selector "resume" "$resume_value"
            else
                set_session_selector "continue"
            fi
            ;;
        --session-id)
            if (( i + 1 >= ${#original_args[@]} )); then
                echo "claude-smart: --session-id requires a UUID" >&2
                exit 64
            fi
            set_session_selector "resume" "${original_args[i + 1]}"
            ;;
        --session-id=*)
            set_session_selector "resume" "${argument#*=}"
            ;;
        -p|--print|--bg|--background|--cloud|--cloud=*|--remote-control|--remote-control=*|--no-session-persistence|--fork-session)
            echo "claude-smart: $argument is incompatible with interactive auto-resume" >&2
            exit 64
            ;;
    esac
done

if ! command -v claude >/dev/null 2>&1; then
    echo "claude-smart: claude is not installed or is not on PATH" >&2
    exit 127
fi

if ! command -v script >/dev/null 2>&1; then
    echo "claude-smart: the script utility is required to preserve the interactive terminal" >&2
    exit 127
fi

if [[ $session_mode == "fresh" ]] && ! command -v uuidgen >/dev/null 2>&1; then
    echo "claude-smart: uuidgen is required to create a resumable session" >&2
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

quote_for_shell() {
    local escaped=${1//\'/\'\\\'\'}
    printf "'%s'" "$escaped"
}

run_claude() {
    local command_line=""
    local command_part

    : > "$log_file"

    if [[ $(uname -s) == "Darwin" ]]; then
        script -q -e "$log_file" "$@"
    else
        for command_part in "$@"; do
            command_line+=" $(quote_for_shell "$command_part")"
        done
        script -q -e -c "exec$command_line" "$log_file"
    fi
}

limit_was_reached() {
    LC_ALL=C grep -aiEq \
        "(usage|rate|session)[[:space:]-]+limit.{0,40}(reached|exceeded)|you.?ve hit your.{0,20}limit|quota exceeded|limit.{0,40}resets at" \
        "$log_file"
}

retry_count=0

case $session_mode in
    fresh)
        session_id=$(uuidgen | tr '[:upper:]' '[:lower:]')
        initial_command=(claude --session-id "$session_id" "${original_args[@]}")
        retry_command=(claude --resume "$session_id" "$RESUME_PROMPT")
        echo "Starting a fresh Claude Code session ($session_id)."
        ;;
    resume)
        initial_command=(claude "${original_args[@]}")
        retry_command=(claude --resume "$session_id" "$RESUME_PROMPT")
        echo "Starting the requested Claude Code session."
        ;;
    continue)
        initial_command=(claude "${original_args[@]}")
        retry_command=(claude --continue "$RESUME_PROMPT")
        echo "Starting the requested Claude Code session."
        ;;
esac

current_command=("${initial_command[@]}")

while true; do
    run_claude "${current_command[@]}"
    claude_exit=$?

    if limit_was_reached; then
        retry_count=$((retry_count + 1))

        if (( MAX_RETRIES > 0 && retry_count > MAX_RETRIES )); then
            echo "Claude Code still reports a usage limit after $MAX_RETRIES retries; stopping." >&2
            exit 75
        fi

        echo "Claude Code reported a usage limit. Retrying in $RETRY_SECONDS seconds."
        sleep "$RETRY_SECONDS"
        current_command=("${retry_command[@]}")
        continue
    fi

    if (( claude_exit == 0 )); then
        echo "Claude Code exited normally."
        exit 0
    fi

    echo "Claude Code exited with status $claude_exit and no usage-limit message; stopping." >&2
    exit "$claude_exit"
done
