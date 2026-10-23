# FW01 rule set for domain join, logging, and PKI (build before FS01 / WS01-03)

All rules are **Pass** with **Log** ticked unless stated. OPNsense is default-deny, so anything not listed stays blocked and is logged.
Add rules under **Firewall > Rules > [interface]**. Rule order matters only for block rules, which are last.

## 1. Aliases (Firewall > Aliases > +)

| Name | Type | Content |
|---|---|---|
| `DC_HOSTS` | Host(s) | `10.50.0.10`, `10.50.0.11` |
| `SIEM_HOST` | Host(s) | `10.50.0.20` |
| `PKI_ISS_HOST` | Host(s) | `10.50.0.12` |
| `AD_TCP` | Port(s) | `53, 88, 135, 389, 445, 464, 636, 3268, 3269` |
| `AD_UDP` | Port(s) | `53, 88, 123, 389, 464` |
| `RPC_DYNAMIC` | Port(s) | `49152:65535` |
| `WAZUH_PORTS` | Port(s) | `1514, 1515` |
| `WEB_PORTS` | Port(s) | `80, 443` |

Save and Apply after creating the aliases.

## 2. Rename the interfaces (Interfaces > [OPTn])
LAN = `Corp`, OPT1 = `CUI`, OPT2 = `DMZ`, OPT3 = `Admin`, OPT4 = `Attack`.

## 3. CUI interface (source: CUI net)

| # | Proto | Destination | Port | Purpose |
|---|---|---|---|---|
| 1 | TCP | `DC_HOSTS` | `AD_TCP` | DNS, Kerberos, RPC endpoint mapper, LDAP, SMB, GC |
| 2 | UDP | `DC_HOSTS` | `AD_UDP` | DNS, Kerberos, NTP, LDAP |
| 3 | TCP | `DC_HOSTS` | `RPC_DYNAMIC` | Domain join, group policy, replication RPC |
| 4 | TCP | `SIEM_HOST` | `WAZUH_PORTS` | Wazuh agent enrollment and events |
| 5 | TCP | `PKI_ISS_HOST` | `WEB_PORTS` | CRL and AIA download over HTTP |
| 6 | TCP | `PKI_ISS_HOST` | `135` and `RPC_DYNAMIC` | Certificate autoenrollment (RPC/DCOM) |
| 7 | any | any | any | **Block**, log (explicit end-of-list deny, documents the boundary) |

The CUI enclave gets **no internet access** and no path to Corp, DMZ, or Attack.

## 4. Corp interface (source: Corp net)
First **delete or disable** the two default "allow LAN to any" rules.

| # | Proto | Destination | Port | Purpose |
|---|---|---|---|---|
| 1-3 | same as CUI rules 1-3 | `DC_HOSTS` | | Domain services |
| 4 | TCP | `SIEM_HOST` | `WAZUH_PORTS` | Wazuh agents |
| 5-6 | same as CUI rules 5-6 | `PKI_ISS_HOST` | | PKI |
| 7 | TCP | **This Firewall excluded**, any outside | `WEB_PORTS` | Internet browsing (destination: `!RFC1918` if you create that alias) |
| 8 | TCP | FS01 (`10.30.0.x`) | `3389, 445` | Controlled access to the enclave file server. Add after FS01 has an address |
| 9 | any | any | any | **Block**, log |

## 5. Admin interface
The temporary "TEMP build access" rule stays for now (it supports Windows Update and package downloads on the Admin VMs). Replace it with specific rules in Phase 6c, once the labs are built.

## 6. Rules the firewall itself needs
- **Floating or Admin:** allow `DC_HOSTS` and `SIEM_HOST` out to `WAN` for updates (the TEMP rule already covers this for now).
- Do **not** open any path from CUI or Corp to `Admin` except the services above.

## 7. Test each rule (this is your evidence)
For each allow rule: from a VM on that segment, test the port (`Test-NetConnection <dc> -Port 389`). For each block: confirm it fails and that a deny entry appears in **Firewall > Log Files > Live View** and in Wazuh. Screenshot both. These pass/fail results are the assessment evidence for boundary protection (SC.L2-3.13.1 and 3.13.6).

## Order of work
1. Create aliases, rename interfaces.
2. CUI rules 1-7, Corp rules 1-6 and 9.
3. Build and install FS01 and WS01-03 (static IPs; DNS = `10.50.0.10`, `10.50.0.11`).
4. Join the domain, then test each rule and capture the evidence.
