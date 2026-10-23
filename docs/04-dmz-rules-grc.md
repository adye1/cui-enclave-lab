# GRC01 (DMZ): firewall rules and build notes

GRC01 holds the SSP, control mappings, evidence links, risk register, and POA&M. It is not part of the CUI enclave, so it lives in the DMZ with its own narrow rules.

## 1. New aliases (Firewall > Aliases)

| Name | Type | Content |
|---|---|---|
| `GRC_HOST` | Host(s) | `10.40.0.20` |
| `GRC_ADMIN_PORTS` | Port(s) | `22, 8443` |
| `DNS_PORT` | Port(s) | `53` |

(`DC_HOSTS`, `SIEM_HOST`, `WEB_PORTS`, `RFC1918` already exist from the Corp and CUI work.)

## 2. DMZ interface rules (source: DMZ net). Pass, Log ticked, final Block last.

| # | Proto | Destination | Port | Purpose |
|---|---|---|---|---|
| 1 | TCP/UDP | `DC_HOSTS` | `DNS_PORT` | Name resolution through the domain controllers |
| 2 | TCP | `! RFC1918` (invert) | `WEB_PORTS` | Package and container downloads during install (remove or restrict afterwards) |
| 3 | UDP | `DC_HOSTS` | `123` | Time sync |
| 4 | TCP | `SIEM_HOST` | `WAZUH_PORTS` | Optional Wazuh agent on GRC01 |
| 5 | any | any | any | **Block**, log |

DMZ has no path to Corp, CUI, or Attack, and no management path to the firewall.

## 3. Reaching GRC01 from your host (a temporary management path)
Your host is on Lab-WAN, so it needs a route and one WAN rule:

- **Host (elevated):** `New-NetRoute -DestinationPrefix 10.40.0.0/24 -InterfaceAlias "vEthernet (Lab-WAN)" -NextHop 192.168.100.2`
- **OPNsense, Firewall > Rules > WAN:** two Pass rules, TCP from `192.168.100.1/32` to `GRC_HOST` on `22` and on `8443`, Log ticked.

Add this to the Phase 6 cleanup list: when the management VM replaces the host as the admin path, delete these WAN rules.

## 4. VM build
- Host: `.\02-New-LabVMs.ps1 -Only GRC01` (8GB RAM, 2 vCPU, 100GB, on Lab-DMZ).
- Install Ubuntu Server 24.04: hostname `grc01`, install OpenSSH, static IPv4 `10.40.0.20/24`, gateway `10.40.0.1`, DNS `10.50.0.10,10.50.0.11`.
- From inside GRC01 check: `ping -c1 10.40.0.1` is expected to fail (no ICMP rule), so test instead with `nslookup opnsense.org 10.50.0.10` and `curl -sI https://github.com | head -n 1`.

## 5. Install the GRC tool
Use the project's own instructions, which are the authority for the current commands:
- **Docker Engine:** docs.docker.com, "Install Docker Engine on Ubuntu" (the apt repository method).
- **CISO Assistant (community edition):** the `intuitem/ciso-assistant-community` repository on GitHub. Its README describes cloning the repository and running the Docker Compose setup script, creating the first admin, and the default HTTPS port (the rules above assume `8443`; if the README says otherwise, change the alias).
- Record the Docker and application versions in `F:\Evidence\GRC01\versions.txt`.

## 6. After install
1. Create an administrator account with a password from your password manager.
2. Load the NIST SP 800-171 Rev 2 framework (and the CMMC Level 2 framework if present in the library).
3. Create a project for the enclave and scope it: FS01, WS01, DC01/DC02, PKI-ISS, SIEM01, FW01.
4. Attach evidence from `F:\Evidence` to each control, using `03-evidence-checklist.md` as the map.
