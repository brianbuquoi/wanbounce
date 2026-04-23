#!/bin/bash
# wan-bounce installer for UniFi UDM-series hardware (tested on UDM SE).
# Run as root from the cloned repo directory:  sudo ./install.sh

set -euo pipefail

SCRIPT_DIR="/data/scripts"
BOOT_HOOK_DIR="/data/on_boot.d"
SYSTEMD_DIR="/etc/systemd/system"
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ "$(id -u)" -ne 0 ]; then
    echo "Must be run as root." >&2
    exit 1
fi

mkdir -p "$SCRIPT_DIR"

install -m 0755 "$REPO_DIR/wan-bounce.sh"      "$SCRIPT_DIR/wan-bounce.sh"
install -m 0644 "$REPO_DIR/wan-bounce.service" "$SCRIPT_DIR/wan-bounce.service"
install -m 0644 "$REPO_DIR/wan-bounce.service" "$SYSTEMD_DIR/wan-bounce.service"

if [ -d "$BOOT_HOOK_DIR" ]; then
    install -m 0755 "$REPO_DIR/on_boot.d/15-wan-bounce.sh" "$BOOT_HOOK_DIR/15-wan-bounce.sh"
    echo "Boot hook installed at $BOOT_HOOK_DIR/15-wan-bounce.sh (will restore service after firmware updates)."
else
    cat <<EOF
WARNING: $BOOT_HOOK_DIR does not exist.
The service will survive reboots but NOT firmware updates unless udm-boot
(from unifios-utilities) is installed. See README for details.
EOF
fi

systemctl daemon-reload
systemctl enable wan-bounce.service
systemctl restart wan-bounce.service

echo
echo "Installed. Status:"
systemctl --no-pager status wan-bounce.service | head -n 10 || true
echo
echo "Follow logs with:  journalctl -u wan-bounce -f"
echo "Or:                tail -f /var/log/wan-bounce.log"
