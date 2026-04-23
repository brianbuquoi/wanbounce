#!/bin/bash

INTERFACE="eth9"
CHECK_INTERVAL=10       # seconds between checks
REQUIRED_FAILURES=3     # 3 * 10s = 30 seconds continuous failure before bounce
COOLDOWN=7200           # 2 hours in seconds
LOGFILE="/var/log/wan-bounce.log"
PING_TARGETS=("1.1.1.1" "8.8.8.8")
PING_COUNT=1
PING_TIMEOUT=2

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOGFILE"
}

is_wan_down() {
    for target in "${PING_TARGETS[@]}"; do
        if ping -I "$INTERFACE" -c "$PING_COUNT" -W "$PING_TIMEOUT" -q "$target" &>/dev/null; then
            return 1  # at least one target reachable — WAN is up
        fi
    done
    return 0  # all targets failed — WAN is down
}

log "WAN monitor started. Interface: $INTERFACE. Threshold: ${REQUIRED_FAILURES}x${CHECK_INTERVAL}s. Cooldown: ${COOLDOWN}s."
log "Ping targets: ${PING_TARGETS[*]}"

fail_count=0
cooldown_until=0

while true; do
    now=$(date +%s)

    if [ "$now" -lt "$cooldown_until" ]; then
        remaining=$(( cooldown_until - now ))
        if [ $(( remaining % 300 )) -lt "$CHECK_INTERVAL" ]; then
            log "In cooldown. ${remaining}s remaining before re-arming."
        fi
        fail_count=0
        sleep "$CHECK_INTERVAL"
        continue
    fi

    if is_wan_down; then
        (( fail_count++ ))
        log "WAN unreachable (${fail_count}/${REQUIRED_FAILURES}) — no response from ${PING_TARGETS[*]} via $INTERFACE"

        if [ "$fail_count" -ge "$REQUIRED_FAILURES" ]; then
            log "WAN down for $((REQUIRED_FAILURES * CHECK_INTERVAL))s. Bouncing $INTERFACE..."
            ip link set dev "$INTERFACE" down
            sleep 3
            ip link set dev "$INTERFACE" up
            cooldown_until=$(( $(date +%s) + COOLDOWN ))
            log "Bounce complete. Entering ${COOLDOWN}s cooldown. Re-arms at $(date -d @${cooldown_until} '+%Y-%m-%d %H:%M:%S')."
            fail_count=0
        fi
    else
        if [ "$fail_count" -gt 0 ]; then
            log "WAN recovered before threshold (was at ${fail_count}/${REQUIRED_FAILURES}). Resetting."
        fi
        fail_count=0
    fi

    sleep "$CHECK_INTERVAL"
done
