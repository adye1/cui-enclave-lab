# FW01 (OPNsense) configuration plan

## Install
1. Boot FW01 from the OPNsense ISO, log in as `installer`, install to the 30GB disk (ZFS or UFS both fine).
2. Console option 1: assign interfaces in order `hn0..hn5` = WAN, Corp, CUI, DMZ, Admin, Attack (confirm by MAC: hn0 = 00:15:5d:10:00:01 through hn5 = ...06; the console shows each MAC).
3. Console option 2: set LAN-side IPs `.1/24` per the table; set WAN to `192.168.100.2/24`, gateway `192.168.100.1`, DNS `1.1.1.1`.
4. Manage from the web UI at `https://10.50.0.1` from a VM on Lab-Admin (or temporarily from the host via Lab-WAN).

## Default-deny rule matrix
Build the allow rules only; everything else is denied and logged.

| From -> To | Allowed | Why |
|---|---|---|
| CUI -> Admin | DNS, Kerberos, LDAP/S, SMB to DCs; 1514/1515 to SIEM01; 443/80 to PKI-ISS | Domain, logging, cert enrollment |
| CUI -> Corp / DMZ / Attack | none | Enclave boundary |
| CUI -> WAN | none | No internet from the enclave (deny by default) |
| Corp -> CUI | RDP/SMB to FS01 only, from named hosts | Controlled access path |
| Corp -> Admin | DNS, Kerberos, LDAP, SMB (domain), agent traffic to SIEM01 | Domain membership |
| Corp -> WAN | 80/443 | Normal user internet |
| Admin -> any | management ports only (WinRM, SSH, RDP) | Tiered admin |
| DMZ -> Admin | 1514/1515 to SIEM01 | Log forwarding |
| Attack -> Corp, DMZ | any (this is the test traffic) | Adversary simulation |
| Attack -> CUI, Admin | none initially; open one path at a time per test | Keep tests deliberate |
| any -> FW01 mgmt | Admin only | Protect the firewall |

Enable logging on every deny rule and forward OPNsense syslog to SIEM01 once it exists. Those logs are your boundary-protection and audit control evidence. Export `config.xml` to `F:\Evidence` after each milestone.

## Order matters
FW01, then DC01/DC02 (Admin), PKI, SIEM01, FS01/WS, GRC01, ATK01. Take a checkpoint after each installed OS (before configuration) and another when it is hardened.
