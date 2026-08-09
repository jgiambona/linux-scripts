#!/usr/bin/env bash

set -u

readonly REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
readonly WRAPPER="$REPO_ROOT/claude-resume-wrapper.sh"

test_dir=$(mktemp -d "${TMPDIR:-/tmp}/claude-smart-test.XXXXXX") || exit 1
cleanup() {
    rm -rf "$test_dir"
}
trap cleanup EXIT

mkdir "$test_dir/bin"

cat > "$test_dir/bin/claude" <<'MOCK_CLAUDE'
#!/usr/bin/env bash

if [[ ${CLAUDE_SMART_TEST_SELECTED:-stop} == "credits" ]]; then
    echo "You've hit your limit. Resets later."
    echo "What do you want to do?"
    echo "❯ 1. Add funds to continue with usage credits"
    echo "2. Stop and wait for limit to reset"

    IFS= read -r selection
    echo "UNSAFE_SELECTION:$selection"
    exit 1
fi

for ((cycle = 1; cycle <= ${CLAUDE_SMART_TEST_LIMIT_CYCLES:-1}; cycle++)); do
    echo "You've hit your limit. Resets later."
    echo "What do you want to do?"
    echo "❯ 1. Stop and wait for limit to reset"
    echo "2. Add funds to continue with usage credits"

    IFS= read -r selection
    if [[ -n $selection ]]; then
        echo "WRONG_SELECTION:$selection"
        exit 1
    fi

    echo "WAITING_FOR_RESET"
    IFS= read -r response
    if [[ $response != "continue" ]]; then
        echo "WRONG_RESPONSE:$response"
        exit 1
    fi
done

echo "AUTO_RESUMED"
MOCK_CLAUDE
chmod +x "$test_dir/bin/claude"

TEST_BIN="$test_dir/bin" WRAPPER_UNDER_TEST="$WRAPPER" CLAUDE_SMART_TEST_LIMIT_CYCLES=2 expect <<'EXPECT_TEST'
set timeout 7
set env(PATH) "$env(TEST_BIN):$env(PATH)"
set env(CLAUDE_SMART_RETRY_SECONDS) 1
set env(CLAUDE_SMART_MAX_RETRIES) 2

spawn -noecho $env(WRAPPER_UNDER_TEST) --continue
expect {
    "AUTO_RESUMED" {
        expect eof
        exit 0
    }
    "WRONG_SELECTION:" {
        send_error "wrapper selected the wrong rate-limit option\n"
        exit 1
    }
    "WRONG_RESPONSE:" {
        send_error "wrapper sent the wrong recovery response\n"
        exit 1
    }
    timeout {
        send_error "wrapper stalled at the interactive rate-limit menu\n"
        exit 1
    }
    eof {
        send_error "wrapper exited before automatically resuming\n"
        exit 1
    }
}
EXPECT_TEST

TEST_BIN="$test_dir/bin" WRAPPER_UNDER_TEST="$WRAPPER" CLAUDE_SMART_TEST_SELECTED=credits expect <<'EXPECT_SAFETY'
set timeout 2
set env(PATH) "$env(TEST_BIN):$env(PATH)"
set env(CLAUDE_SMART_RETRY_SECONDS) 1

spawn -noecho $env(WRAPPER_UNDER_TEST) --continue
expect {
    "claude-smart: selecting 'Stop and wait'" {
        send_error "wrapper acted while the usage-credit option was selected\n"
        exit 1
    }
    "UNSAFE_SELECTION:" {
        send_error "wrapper selected the usage-credit option\n"
        exit 1
    }
    timeout {
        send -- "\003"
        exit 0
    }
    eof {
        send_error "wrapper exited unexpectedly during the menu safety test\n"
        exit 1
    }
}
EXPECT_SAFETY
