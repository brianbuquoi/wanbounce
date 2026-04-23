# wan-bounce

A small WAN watchdog for UniFi UDM-series gateways. When the WAN interface goes unreachable for a sustained window, `wan-bounce` bounces the link (`ip link down` / `up`) to force the ISP-facing port — and any upstream DHCP/PPPoE session — to re-establish.

Tested on a **UDM SE**.

## Why

Some WAN failure modes don't recover on their own:

- The physical link stays up but the upstream drops you silently.
- DHCP lease survives but the ISP stops routing your traffic.
- An SFP+ transceiver wedges and ignores further carrier events.

In those cases, the UDM won't re-request a lease or renegotiate PPPoE because, from its perspective, nothing changed. Bouncing the interface forces it to.

## What it does

A single bash loop (`wan-bounce.sh`) runs as a systemd service and:

1. Every `CHECK_INTERVAL` seconds (default **10s**), pings `1.1.1.1` and `8.8.8.8` **through the WAN interface only** (`ping -I $INTERFACE`).
2. If *all* targets fail, increments a failure counter.
3. After `REQUIRED_FAILURES` consecutive failures (default **3**, so 30 seconds of solid failure), it runs:
   ```
   ip link set dev $INTERFACE down
   sleep 3
   ip link set dev $INTERFACE up
   ```
4. Enters a `COOLDOWN` window (default **2 hours**) before it's allowed to bounce again. This prevents flapping if an ISP outage is actually long-lived.
5. Logs every state change to `/var/log/wan-bounce.log` and to the journal.

Defaults live at the top of `wan-bounce.sh`:

| Variable | Default | Meaning |
| --- | --- | --- |
| `INTERFACE` | `eth9` | WAN interface to monitor (SFP+ WAN on a UDM SE). Change to `eth8` for the RJ45 WAN port, or whatever matches your setup. |
| `CHECK_INTERVAL` | `10` | Seconds between probes. |
| `REQUIRED_FAILURES` | `3` | Consecutive failed probes before bouncing. |
| `COOLDOWN` | `7200` | Seconds to wait after a bounce before re-arming. |
| `PING_TARGETS` | `1.1.1.1 8.8.8.8` | All must fail for a probe to count as down. |

**Confirm your interface name before installing.** On a UDM SE, `eth8` is typically the RJ45 WAN and `eth9` is the SFP+ WAN, but configurations vary. Run `ip -br link` on the device and match against your WAN port.

## Install

SSH into the UDM as `root`, then:

```sh
mkdir -p /data/scripts
cd /data/scripts
curl -O https://raw.githubusercontent.com/brianbuquoi/wanbounce/main/wan-bounce.sh
curl -O https://raw.githubusercontent.com/brianbuquoi/wanbounce/main/wan-bounce.service
chmod +x wan-bounce.sh

cp /data/scripts/wan-bounce.service /etc/systemd/system/wan-bounce.service
systemctl daemon-reload
systemctl enable --now wan-bounce.service
```

Edit `INTERFACE` (and anything else) at the top of `/data/scripts/wan-bounce.sh`, then `systemctl restart wan-bounce`.

## Verify

```sh
systemctl status wan-bounce
journalctl -u wan-bounce -f
tail -f /var/log/wan-bounce.log
```

You should see a startup banner like:

```
[2026-04-23 22:10:00] WAN monitor started. Interface: eth9. Threshold: 3x10s. Cooldown: 7200s.
[2026-04-23 22:10:00] Ping targets: 1.1.1.1 8.8.8.8
```

## Uninstall

```sh
systemctl disable --now wan-bounce.service
rm /etc/systemd/system/wan-bounce.service
rm /data/scripts/wan-bounce.sh /data/scripts/wan-bounce.service
systemctl daemon-reload
```

## Caveats

- A bounce briefly interrupts all WAN traffic. The 2-hour cooldown keeps that from repeating during a real ISP outage.
- The script assumes an interface that can be brought down and back up without breaking UniFi's internal state. Standard UDM SE WAN ports behave correctly here; exotic setups (bonds, VLAN-tagged WANs on top of other interfaces) may not.
- If your ISP filters `1.1.1.1` and `8.8.8.8` for any reason, swap `PING_TARGETS` for something you trust.
