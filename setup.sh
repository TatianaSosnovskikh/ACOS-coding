#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

sudo install -m 755 "$SCRIPT_DIR/mount_logs.sh" /usr/local/sbin/mount_logs.sh
sudo /usr/local/sbin/mount_logs.sh

echo "LOGS mount setup completed"
