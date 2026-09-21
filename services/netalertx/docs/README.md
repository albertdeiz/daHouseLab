# netalertx — Documentation

Deep documentation for the LAN device monitor. Front page: [`../README.md`](../README.md).

Document here as they happen: scan configuration, notification setup (Telegram gateway), how known
devices were named/grouped, the host firewall rule for port 20211 (source of truth is
[deploy-netalertx](../../../docs/runbooks/deploy-netalertx.md)), and any incident
([documentation conventions](../../../docs/standards/documentation-conventions.md)).

Why before how, always.

## Device discovery: why not every device shows up (and how to tune it)

**Why it matters:** the value of this service is trust in the device list. Knowing *why* a device
is missing prevents both false alarms ("an intruder!") and false confidence ("everything's here").
NetAlertX builds its inventory over many scan cycles from several sources — it is never complete on
the first pass, and ARP has hard physical limits. This is expected behaviour, not a fault.

### What is normal

- **Warm-up:** arp-scan runs on an interval; devices appear as they answer. Allow **several cycles
  (up to ~24 h)** for a full picture.
- **Sleeping devices:** phones and IoT sleep and answer ARP unreliably — they flap between
  present/absent. NetAlertX tracks presence over time rather than a single snapshot.
- **Randomized MACs:** modern phones use per-network random MACs; they appear, but the MAC (the
  identity key) can change between networks.

### Hard limits of ARP (cannot be tuned away)

- **Layer-2 only:** arp-scan sees **only the local segment**. Devices on another subnet/VLAN, or on
  an isolated **guest network**, never appear via ARP — by design.
- **AP/WiFi client isolation:** many routers isolate wireless clients from each other. If the Pi is
  wired, it may get **no ARP replies from isolated WiFi devices** — the #1 cause of "my phone/tablet
  isn't listed." Fix at the router (disable client isolation) or put the Pi on the same WiFi.

### Configuration to verify (web UI → Settings)

- **`SCAN_SUBNETS`** must target the LAN with the correct interface, e.g.
  `192.168.100.0/24 --interface=eth0` (use `wlan0` if the Pi is on WiFi). Wrong interface/subnet =
  wrong or empty results.
- The **arp-scan plugin** is enabled with a sane interval (e.g. every 5 min); check its plugin log
  for interface/permission errors (needs the `NET_RAW`/`NET_ADMIN` caps + host networking, which the
  compose already grants).

### Catching what ARP can't see

Combine discovery sources — do not rely on arp-scan alone:

- **nmap plugin** — ping/TCP sweep of the subnet, for hosts that answer IP but not ARP.
- **DHCP-lease / router (UNIFI, SNMP) import** — surfaces devices the router knows even when
  isolated from the Pi.
- **Pi-hole client import** — now available: [`services/pihole`](../../pihole/README.md) is the
  LAN's resolver since [ADR-0014](../../../docs/decisions/0014-pihole-as-lan-dns-resolver.md), so
  every device that resolves a name is visible to it. This is the best complement to ARP here: it
  catches devices on an isolated guest network or behind AP client isolation, which arp-scan
  structurally cannot see. It does **not** replace ARP discovery — Pi-hole has no MAC identity and
  misses anything with hardcoded DNS, which is precisely why both services exist
  ([ADR-0013](../../../docs/decisions/0013-host-networking-for-lan-scanning.md), Option C).

### Rule of thumb

After a day, with `SCAN_SUBNETS` correct and the arp-scan interval running: if the **WiFi devices**
are the ones missing → almost certainly **AP client isolation**. If devices on **another
subnet/VLAN** are missing → ARP does not cross it; add a router/DHCP import source instead.
