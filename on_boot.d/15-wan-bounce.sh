#!/bin/sh
# wan-bounce boot hook — restores the systemd unit after firmware updates.
# Requires udm-boot (unifios-utilities) to be installed on the UDM.
# Place at /data/on_boot.d/15-wan-bounce.sh and make executable.

SERVICE_SRC="/data/scripts/wan-bounce.service"
SERVICE_DST="/etc/systemd/system/wan-bounce.service"

[ -f "$SERVICE_SRC" ] || exit 0

if [ ! -f "$SERVICE_DST" ] || ! cmp -s "$SERVICE_SRC" "$SERVICE_DST"; then
    cp "$SERVICE_SRC" "$SERVICE_DST"
    systemctl daemon-reload
fi

systemctl enable wan-bounce.service >/dev/null 2>&1
systemctl start wan-bounce.service
