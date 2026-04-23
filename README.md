# wan-bounce

A small WAN watchdog for UniFi UDM-series gateways. When the WAN interface goes unreachable for a sustained window, `wan-bounce` bounces the link (`ip link down` / `up`) to force the ISP-facing port — and any upstream DHCP/PPPoE session — to re-establish.

Tested on a **UDM SE** running UniFi OS 3.x.

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

## Files

```
wan-bounce.sh              # the watchdog script
wan-bounce.service         # systemd unit
install.sh                 # installer — copies files into place, enables the service
uninstall.sh               # removes everything
on_boot.d/
  15-wan-bounce.sh         # boot hook for firmware-update persistence (see below)
```

## Directory layout on the UDM

After installation:

```
/data/scripts/wan-bounce.sh            # the script itself (persistent)
/data/scripts/wan-bounce.service       # source of truth for the unit file (persistent)
/etc/systemd/system/wan-bounce.service # active unit (NOT persistent across firmware updates)
/data/on_boot.d/15-wan-bounce.sh       # restores the unit after firmware updates
/var/log/wan-bounce.log                # script log
```

`/data/` persists across reboots *and* firmware updates. `/etc/systemd/system/` persists across reboots but is wiped on firmware updates, which is why the boot hook exists.

## Installation

SSH into the UDM as `root` (enable SSH from UniFi OS → Console Settings → SSH), then:

```sh
cd /data
git clone https://github.com/brianbuquoi/wanbounce.git
cd wanbounce
./install.sh
```

The installer will:

- Copy `wan-bounce.sh` and `wan-bounce.service` to `/data/scripts/`.
- Copy the unit to `/etc/systemd/system/`.
- Install the `on_boot.d` hook if `/data/on_boot.d` exists.
- `systemctl enable --now wan-bounce.service`.

### Edit config before (or after) install

Edit `INTERFACE` and other settings at the top of `/data/scripts/wan-bounce.sh`, then:

```sh
systemctl restart wan-bounce
```

## Surviving reboots and firmware updates

- **Reboots:** Handled by `systemctl enable wan-bounce.service` — the unit comes up automatically on every boot.
- **Firmware updates:** UniFi OS wipes `/etc/systemd/system/` during firmware upgrades, so a plain systemd install does *not* survive them on its own. To cover this, `wan-bounce` ships an `on_boot.d` hook that re-installs the unit on every boot.

  The hook requires [`udm-boot`](https://github.com/unifi-utilities/unifios-utilities/tree/main/on-boot-script-2.x) (from the `unifios-utilities` project) to be installed on the UDM. If `/data/on_boot.d/` exists, `udm-boot` is already set up and the installer will drop the hook there automatically. If it doesn't, install `udm-boot` first, then re-run `./install.sh`.

The hook is idempotent: it copies the unit file into `/etc/systemd/system/` only when missing or out of date, then enables and starts the service.

## Verifying it's running

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

## Testing the bounce path

With the service stopped, you can rehearse the failure and bounce manually:

```sh
systemctl stop wan-bounce
ping -I eth9 -c 1 -W 2 1.1.1.1     # should succeed when WAN is healthy
ip link set dev eth9 down && sleep 3 && ip link set dev eth9 up
systemctl start wan-bounce
```

Be aware that bouncing the WAN interrupts all internet traffic for a few seconds while the ISP session re-establishes.

## Uninstall

```sh
cd /data/wanbounce
./uninstall.sh
```

This disables the service, removes the unit, the `/data/scripts/` copies, and the boot hook. The log at `/var/log/wan-bounce.log` is left in place.

## Caveats

- The script assumes an interface that can be brought down and back up without breaking UniFi's internal state. The standard UDM SE WAN ports behave correctly here; exotic setups (bonds, VLAN-tagged WANs on top of other interfaces) may not.
- If *both* `1.1.1.1` and `8.8.8.8` are being filtered by your ISP for any reason, the script will bounce unnecessarily. Swap `PING_TARGETS` for something you trust.
- A bounce will briefly interrupt all WAN traffic. The 2-hour cooldown is there to keep that from happening repeatedly during a real outage.
