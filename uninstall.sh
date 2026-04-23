#!/bin/bash
# Remove wan-bounce from a UniFi UDM. Run as root.

set -eu

if [ "$(id -u)" -ne 0 ]; then
    echo "Must be run as root." >&2
    exit 1
fi

systemctl disable --now wan-bounce.service 2>/dev/null || true
rm -f /etc/systemd/system/wan-bounce.service
rm -f /data/scripts/wan-bounce.service
rm -f /data/scripts/wan-bounce.sh
rm -f /data/on_boot.d/15-wan-bounce.sh
systemctl daemon-reload

echo "wan-bounce removed. Log file at /var/log/wan-bounce.log was left in place."
