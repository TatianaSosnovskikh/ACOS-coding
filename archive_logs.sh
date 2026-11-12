#!/bin/bash
set -euo pipefail

LOGS_DIR="${LOGS_DIR:-/LOGS}"
THRESHOLD="${THRESHOLD:-90}"
BATCH_SIZE="${BATCH_SIZE:-10}"
TEST_TOTAL_KB="${TEST_TOTAL_KB:-}"

SERVICES=(
    "auth_service"
    "data_process_service"
    "system_event_handler_service"
)

if [[ ! "$THRESHOLD" =~ ^[0-9]+$ ]] || (( THRESHOLD < 1 || THRESHOLD > 100 )); then
    echo "Invalid threshold"
    exit 1
fi

if [[ ! "$BATCH_SIZE" =~ ^[1-9][0-9]*$ ]]; then
    echo "Invalid batch size"
    exit 1
fi

if [[ ! -d "$LOGS_DIR" ]]; then
    echo "Logs directory does not exist"
    exit 1
fi

if [[ -n "$TEST_TOTAL_KB" ]]; then
    if [[ ! "$TEST_TOTAL_KB" =~ ^[1-9][0-9]*$ ]]; then
        echo "Invalid test capacity"
        exit 1
    fi
    TOTAL_KB="$TEST_TOTAL_KB"
USED_KB=0

for SERVICE in "${SERVICES[@]}"; do
    DIR="$LOGS_DIR/$SERVICE"
    if [[ -d "$DIR" ]]; then
        DIR_SIZE=$(du -sk "$DIR" | awk '{print $1}')
        USED_KB=$((USED_KB + DIR_SIZE))
    fi
done
else
    read -r TOTAL_KB USED_KB < <(
        df -Pk "$LOGS_DIR" | awk 'NR == 2 {print $2, $3}'
    )
fi

if (( TOTAL_KB == 0 )); then
    echo "Cannot determine filesystem capacity"
    exit 1
fi

USED_PERCENT=$(( USED_KB * 100 / TOTAL_KB ))

echo "Filesystem usage: ${USED_PERCENT}%"
echo "Archive threshold: ${THRESHOLD}%"

if (( USED_PERCENT < THRESHOLD )); then
    echo "Threshold not exceeded"
    exit 0
fi

FOLDER_LIMIT_KB=$(( TOTAL_KB * THRESHOLD / 100 / 3 ))

echo "Per-folder limit: ${FOLDER_LIMIT_KB} KB"

for SERVICE in "${SERVICES[@]}"; do
    DIR="$LOGS_DIR/$SERVICE"

    if [[ ! -d "$DIR" ]]; then
        echo "Skipping missing directory: $DIR"
        continue
    fi

    DIR_SIZE=$(du -sk "$DIR" | awk '{print $1}')

    if (( DIR_SIZE <= FOLDER_LIMIT_KB )); then
        echo "Within limit: $SERVICE ($DIR_SIZE KB)"
        continue
    fi

    echo "Over limit: $SERVICE ($DIR_SIZE KB)"

    mapfile -t FILES < <(
        find "$DIR" -maxdepth 1 -type f -name '*.log' \
            -printf '%T@ %f\n' |
            sort -n |
            head -n "$BATCH_SIZE" |
            cut -d' ' -f2-
    )

    if (( ${#FILES[@]} < 2 )); then
        echo "Not enough log files to archive: $SERVICE"
        continue
    fi

    ARCHIVE="$DIR/archive_$(date +%Y%m%d_%H%M%S)_$$.tar.gz"

    if tar -czf "$ARCHIVE" -C "$DIR" -- "${FILES[@]}"; then
        for FILE in "${FILES[@]}"; do
            rm -- "$DIR/$FILE"
        done
        echo "Created archive: $ARCHIVE"
    else
        rm -f -- "$ARCHIVE"
        echo "Archive failed: $SERVICE"
        exit 1
    fi
done

echo "Archiving finished"
