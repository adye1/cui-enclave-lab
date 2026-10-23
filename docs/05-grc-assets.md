# CISO Assistant: asset settings to work from

Use this as the single source for creating the assets in **Assets Management > Assets**.
All assets are fictional lab systems in the domain **CUI Enclave Lab**. No real CUI exists anywhere in the lab.

## Settings that are the same for every asset
| Field | Value |
|---|---|
| Domain | `CUI Enclave Lab` |
| Assigned to | `admin@lab.internal` |
| Class | leave blank |
| Disaster Recovery objectives, DORA specific | skip |

## Suggested ratings (1 = lowest, 4 = highest)
These are documented judgments for a lab, entered under *Security capabilities* (supporting assets) or *Security targets* (primary asset).
Keep them consistent with each other. Change them if you disagree, but write down why.

| Asset | Confidentiality | Integrity | Availability |
|---|---|---|---|
| Mock CUI file share (primary) | 4 | 3 | 2 |
| FS01 | 4 | 3 | 2 |
| WS01 | 3 | 3 | 2 |
| FW01 | 3 | 4 | 3 |
| DC01, DC02 | 3 | 4 | 3 |
| SIEM01 | 3 | 4 | 2 |
| PKI-ISS | 3 | 4 | 2 |
| PKI-ROOT | 4 | 4 | 1 |
| GRC01 | 2 | 3 | 1 |
| WS02, WS03 | 2 | 2 | 1 |
| Hyper-V host | 3 | 4 | 3 |

## Order of creation
1. Mock CUI file share (primary), done first.
2. FS01, WS01.
3. FW01, DC01, DC02, SIEM01.
4. PKI-ISS, PKI-ROOT, GRC01, WS02, WS03, Hyper-V host.
5. Return to FS01 and fill in its **Depends on**, because the systems it depends on only exist after step 3.

---

## 1. Mock CUI file share (PRIMARY)
- **Name:** `Mock CUI file share (\\FS01\CUI)`
- **Type:** Primary
- **Is a dependency of:** leave blank (it is the top of the chain)
- **Depends on:** FS01, WS01, DC01, DC02, FW01, SIEM01 (add after those exist)
- **Description:**
```
Mock CUI file share on FS01, used to demonstrate CUI protections in a lab enclave.
All content is fictional and is not real CUI.
Access is limited to the CUI-Users group. SMB signing and encryption are required.
File access is audited and forwarded to the SIEM.
```

## 2. FS01
- **Type:** Supporting
- **Is a dependency of:** Mock CUI file share
- **Depends on:** DC01, DC02, FW01, SIEM01
- **Description:**
```
Role: File server (Windows Server 2025), 10.30.0.10, Lab-CUI segment.
Category: CUI asset. Hosts the mock CUI share \\FS01\CUI.
Provides: SMB share with encryption and signing required, NTFS access by group, file-access auditing.
```

## 3. WS01
- **Type:** Supporting
- **Is a dependency of:** Mock CUI file share
- **Depends on:** DC01, DC02, FW01, SIEM01
- **Description:**
```
Role: Enclave workstation (Windows 11 Enterprise LTSC), 10.30.0.21, Lab-CUI segment.
Category: CUI asset. Authorized client for the mock CUI share.
Provides: access to \\FS01\CUI for CUI-Users. No internet access by design.
```

## 4. FW01
- **Type:** Supporting
- **Is a dependency of:** Mock CUI file share, FS01
- **Depends on:** SIEM01
- **Description:**
```
Role: Boundary firewall (OPNsense 26.7). Interfaces: Corp 10.20.0.1, CUI 10.30.0.1, DMZ 10.40.0.1, Admin 10.50.0.1, Attack 10.60.0.1, WAN 192.168.100.2.
Category: Security protection asset.
Provides: segmentation with default deny, rule logging, log forwarding to the SIEM (syslog UDP 514).
Known exceptions: temporary rules for lab-host management and DMZ web access (see POA&M).
```

## 5. DC01
- **Type:** Supporting
- **Is a dependency of:** Mock CUI file share, FS01
- **Depends on:** FW01, SIEM01
- **Description:**
```
Role: Domain controller and DNS (Windows Server 2025), 10.50.0.10, Lab-Admin segment.
Category: Security protection asset.
Provides: authentication, DNS, group policy (LAB-Baseline-Security), tiered admin OUs, password and lockout policy.
```

## 6. DC02
- **Type:** Supporting
- **Is a dependency of:** Mock CUI file share, FS01
- **Depends on:** FW01, SIEM01
- **Description:**
```
Role: Second domain controller and DNS (Windows Server 2025), 10.50.0.11, Lab-Admin segment.
Category: Security protection asset.
Provides: redundancy for authentication and DNS; replicates with DC01.
```

## 7. SIEM01
- **Type:** Supporting
- **Is a dependency of:** Mock CUI file share, FS01
- **Depends on:** FW01
- **Description:**
```
Role: SIEM (Ubuntu Server 24.04.5, Wazuh 4.14.9 all-in-one), 10.50.0.20, Lab-Admin segment.
Category: Security protection asset.
Provides: audit log collection, agents on lab Windows systems, firewall syslog, file-integrity monitoring of C:\Shares\CUI.
```

## 8. PKI-ISS
- **Type:** Supporting
- **Is a dependency of:** leave blank for now. Add FS01 once certificate autoenrollment is in place (planned, not yet implemented)
- **Depends on:** DC01, DC02, PKI-ROOT
- **Description:**
```
Role: Enterprise issuing CA (Windows Server 2025), 10.50.0.12, Lab-Admin segment. Publishes CRL and certificates over HTTP.
Category: Security protection asset.
Provides: certificate issuance chained to the offline root.
```

## 9. PKI-ROOT
- **Type:** Supporting
- **Is a dependency of:** PKI-ISS
- **Depends on:** leave blank
- **Description:**
```
Role: Offline root CA (Windows Server 2025, standalone, not domain-joined). Powered off except to sign subordinate CAs or renew its CRL.
Network: a NIC on the isolated Lab-Isolated switch that no other VM uses.
Category: Security protection asset.
Provides: root of trust for the PKI.
```

## 10. GRC01
- **Type:** Supporting
- **Is a dependency of:** leave blank
- **Depends on:** FW01
- **Description:**
```
Role: GRC platform (Ubuntu Server 24.04.5, CISO Assistant community edition in Docker), 10.40.0.20, Lab-DMZ segment.
Category: Supporting asset, outside the CUI boundary. Holds assessment records only; no CUI.
Access: SSH tunnel from the lab host only; the web interface listens on localhost.
```

## 11. WS02
- **Type:** Supporting
- **Is a dependency of:** leave blank
- **Depends on:** DC01, DC02, FW01
- **Description:**
```
Role: Corporate workstation (Windows 11 Enterprise LTSC), 10.20.0.21, Lab-Corp segment.
Category: Out of the CUI enclave. Used to test that a non-authorized user is denied access to the share.
Note: a firewall rule permits SMB from Corp to FS01 for testing; access is blocked by file permissions (tested).
```

## 12. WS03
- **Type:** Supporting
- **Is a dependency of:** leave blank
- **Depends on:** DC01, DC02, FW01
- **Description:**
```
Role: Corporate workstation (Windows 11 Enterprise LTSC), 10.20.0.22, Lab-Corp segment.
Category: Out of the CUI enclave.
```

## 13. Hyper-V host (HP Z840)
- **Type:** Supporting
- **Is a dependency of:** leave blank
- **Depends on:** leave blank
- **Description:**
```
Role: Hyper-V host (HP Z840, Windows 11 Pro) running every lab VM. Attached to Lab-WAN at 192.168.100.1.
Category: Underlying infrastructure; not assessed.
Known exceptions: acts as the temporary management path (route to the lab segments and WAN rules for SSH). See POA&M.
```

---

## Known exceptions to carry into the POA&M
1. Temporary Admin-segment "allow all" rule on FW01 (build access).
2. Temporary DMZ web rule for GRC01 package downloads.
3. Host-based management path (route plus WAN rules).
4. Certificate autoenrollment not yet implemented (PKI-ISS to FS01 dependency not recorded).
5. Corp-to-FS01 SMB rule retained for access testing; justify or remove.
