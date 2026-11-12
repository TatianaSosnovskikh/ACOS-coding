#!/bin/bash
set -e

MOUNT_POINT="/LOGS"

mkdir -p "$MOUNT_POINT"

if mountpoint -q "$MOUNT_POINT"; then
    echo "$MOUNT_POINT is already mounted"
else
    mount "$MOUNT_POINT"
    echo "$MOUNT_POINT mounted successfully"
fi
