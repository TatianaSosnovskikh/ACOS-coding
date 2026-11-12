#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ARCHIVER="$SCRIPT_DIR/archive_logs.sh"
TEST_ROOT="$(mktemp -d)"

trap 'rm -rf "$TEST_ROOT"' EXIT

create_logs() {
    local dir="$1"
    local count="$2"
    local size_kb="$3"

    mkdir -p "$dir"

    for ((i = 1; i <= count; i++)); do
        dd if=/dev/zero of="$dir/test_$i.log" \
            bs=1024 count="$size_kb" status=none
    done
}

run_archiver() {
    LOGS_DIR="$1" \
    TEST_TOTAL_KB=3000 \
    THRESHOLD=90 \
    BATCH_SIZE=10 \
    bash "$ARCHIVER"
}

PASS=0
FAIL=0

run_test() {
    local name="$1"
    local result="$2"

    if [[ "$result" == "true" ]]; then
        echo "PASS: $name"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $name"
        FAIL=$((FAIL + 1))
    fi
}

POSITIVE="$TEST_ROOT/positive"
mkdir -p "$POSITIVE"

create_logs "$POSITIVE/auth_service" 2 500
create_logs "$POSITIVE/data_process_service" 2 500
create_logs "$POSITIVE/system_event_handler_service" 2 400

run_archiver "$POSITIVE"

AUTH_ARCHIVES=$(find "$POSITIVE/auth_service" -maxdepth 1 -type f -name '*.tar.gz' | awk 'END {print NR}')
DATA_ARCHIVES=$(find "$POSITIVE/data_process_service" -maxdepth 1 -type f -name '*.tar.gz' | awk 'END {print NR}')
EVENT_ARCHIVES=$(find "$POSITIVE/system_event_handler_service" -maxdepth 1 -type f -name '*.tar.gz' | awk 'END {print NR}')

AUTH_LOGS=$(find "$POSITIVE/auth_service" -maxdepth 1 -name '*.log' | wc -l)
DATA_LOGS=$(find "$POSITIVE/data_process_service" -maxdepth 1 -name '*.log' | wc -l)
EVENT_LOGS=$(find "$POSITIVE/system_event_handler_service" -maxdepth 1 -name '*.log' | wc -l)

run_test "Over-limit folders are archived" \
    "$([[ "$AUTH_ARCHIVES" -eq 1 && "$DATA_ARCHIVES" -eq 1 ]] && echo true || echo false)"

run_test "Original logs are removed after archiving" \
    "$([[ "$AUTH_LOGS" -eq 0 && "$DATA_LOGS" -eq 0 ]] && echo true || echo false)"

run_test "Folder within limit is not archived" \
    "$([[ "$EVENT_ARCHIVES" -eq 0 && "$EVENT_LOGS" -eq 2 ]] && echo true || echo false)"

NEGATIVE="$TEST_ROOT/negative"
mkdir -p "$NEGATIVE"

create_logs "$NEGATIVE/auth_service" 2 300
create_logs "$NEGATIVE/data_process_service" 2 300
create_logs "$NEGATIVE/system_event_handler_service" 2 300

run_archiver "$NEGATIVE"

NEGATIVE_ARCHIVES=$(find "$NEGATIVE" -type f -name '*.tar.gz' | wc -l)
NEGATIVE_LOGS=$(find "$NEGATIVE" -type f -name '*.log' | wc -l)

run_test "Below-threshold data is not archived" \
    "$([[ "$NEGATIVE_ARCHIVES" -eq 0 && "$NEGATIVE_LOGS" -eq 6 ]] && echo true || echo false)"

run_test "Invalid threshold is rejected" \
    "$(
        if LOGS_DIR="$NEGATIVE" THRESHOLD=101 \
            bash "$ARCHIVER" >/dev/null 2>&1; then
            echo false
        else
            echo true
        fi
    )"

FAILURE="$TEST_ROOT/failure"
FAKE_BIN="$TEST_ROOT/fake_bin"

mkdir -p "$FAKE_BIN"
create_logs "$FAILURE/auth_service" 2 300

cat > "$FAKE_BIN/tar" <<'EOF'
#!/bin/bash
exit 1
EOF

chmod +x "$FAKE_BIN/tar"

if PATH="$FAKE_BIN:$PATH" \
    LOGS_DIR="$FAILURE" \
    TEST_TOTAL_KB=500 \
    THRESHOLD=90 \
    BATCH_SIZE=10 \
    bash "$ARCHIVER" >/dev/null 2>&1; then
    ARCHIVE_FAILED=false
else
    ARCHIVE_FAILED=true
fi

REMAINING_LOGS=$(find "$FAILURE/auth_service" \
    -maxdepth 1 -type f -name '*.log' | wc -l)

REMAINING_ARCHIVES=$(find "$FAILURE/auth_service" \
    -maxdepth 1 -type f -name '*.tar.gz' | wc -l)

run_test "Archive failure preserves original logs" \
    "$([[ "$ARCHIVE_FAILED" == true && "$REMAINING_LOGS" -eq 2 && "$REMAINING_ARCHIVES" -eq 0 ]] && echo true || echo false)"

echo "Passed: $PASS"
echo "Failed: $FAIL"

if (( FAIL > 0 )); then
    exit 1
fi
