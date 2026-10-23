# Evidence checklist and control map (CUI enclave, Phases 1-5)

Control references use NIST SP 800-171 Rev 2 requirement numbers (the basis of CMMC Level 2).
Verify each mapping against the official publication or the CMMC assessment guide before relying on it in a real assessment.
Evidence lives under `F:\Evidence\<system>\`. Everything under that folder is hashed by `08-Collect-Evidence.ps1`.

| # | What it shows | Requirement | Artifact | Where it comes from | Saved as |
|---|---|---|---|---|---|
| 1 | Network segmentation, default-deny | 3.13.1, 3.13.5, 3.13.6 | OPNsense config export | System > Configuration > Backups | `FW01\fw01-config-<date>.xml` |
| 2 | Firewall rule set (CUI, Corp) | 3.13.1, 3.13.6, 3.1.3 | Screenshots of Firewall > Rules > CUI and Corp | OPNsense GUI | `FW01\rules-cui.png`, `rules-corp.png` |
| 3 | Enclave has no internet egress | 3.13.6 | WS01 test transcript line `PASS Internet from the enclave` plus the matching `block` row | `WS01-access-tests.txt`; Live View screenshot | `WS01\...`, `FW01\liveview-ws01-egress-block.png` |
| 4 | Corp cannot reach CUI services except SMB | 3.13.1, 3.1.3 | WS02 transcript (RDP, SIEM denied) and `block` rows | `WS02-access-tests.txt`; Live View | `WS02\...`, `FW01\liveview-ws02-blocks.png` |
| 5 | Authorized user can access CUI | 3.1.1, 3.1.2 | WS01 transcript (member of CUI-Users, read, write) | `WS01-access-tests.txt` | `WS01\...` |
| 6 | Unauthorized user denied by permissions | 3.1.1, 3.1.2, 3.1.5 | WS02 transcript `Access is denied` plus `pass` row for port 445 | `WS02-access-tests.txt`; Live View | `WS02\...`, `FW01\liveview-ws02-smb-pass.png` |
| 7 | Group-based access, least privilege | 3.1.5, 3.1.2 | AD group membership and NTFS ACL | `ad-group-membership.txt`, `fs01-ntfs-acl.txt` | `DC01\...`, `FS01\...` |
| 8 | Password and lockout policy | 3.5.7, 3.5.8, 3.1.8 | `ad-password-policy.txt` | `04-AD-Structure.ps1` | `DC01\...` |
| 9 | Session lock and login banner | 3.1.10, 3.1.9 | GPO report `gpo-LAB-Baseline-Security.html` and a screenshot of the banner on a CUI machine | `04-AD-Structure.ps1`; WS01 login screen | `DC01\...`, `WS01\banner.png` |
| 10 | Encryption of CUI in transit | 3.13.8 | `fs01-smbconfig.txt` (signing and encryption required, SMB1 off), `fs01-smbshare.txt` | `11-FS01-Config.ps1` | `FS01\...` |
| 11 | Audit logging enabled | 3.3.1, 3.3.2 | `fs01-auditpol.txt` | `11-FS01-Config.ps1` | `FS01\...` |
| 12 | Audit events reach the SIEM and are attributable | 3.3.1, 3.3.2, 3.14.6 | Wazuh screenshots: FS01 events for `cui.user1` (success) and `corp.user1` (failure) | Wazuh > Threat Hunting > Events | `SIEM01\wazuh-fs01-cui.user1.png`, `wazuh-fs01-corp.user1-denied.png` |
| 13 | All lab systems report to the SIEM | 3.14.6, 3.14.7 | Wazuh Endpoints page showing every agent Active | Wazuh > Endpoints | `SIEM01\wazuh-agents-active.png` |
| 14 | Firewall logs forwarded to the SIEM | 3.3.1, 3.13.1 | Wazuh events from `10.50.0.1` | Wazuh > Threat Hunting | `SIEM01\wazuh-firewall-events.png` |
| 15 | PKI chain of trust | 3.13.8, 3.13.10 | `root-cainfo.txt`, `issuing-cainfo.txt`, `issuing-chain-verify.txt` | PKI scripts | `PKI-ROOT\...`, `PKI-ISS\...` |
| 16 | Baseline configuration and change record | 3.4.1, 3.4.2 | VM checkpoints list, `labs\scripts` repository history, this checklist | `Get-VMSnapshot * \| Select VMName,Name,CreationTime` | `host\checkpoints.txt` |
| 17 | Directory health | 3.12.1 | `ad-replication.txt`, `dcdiag.txt` | `04-AD-Structure.ps1` | `DC01\...` |

## Wazuh searches for items 12-14
In Wazuh open **Threat Hunting > Events**, set the time range to cover the test, then filter:
- FS01 and a user: `agent.name: FS01` and search for `cui.user1` or `corp.user1`.
- Failed share access: search for `5145` (a share object was accessed) and look at the access result; also `4625` for failed logons.
- Firewall events: search `10.50.0.1` or `filterlog`.
Screenshot with the filter and the time range visible.

## Rules for captured screenshots
- Include the browser address bar or the page header and a visible timestamp.
- Name every file as in the table. Do not edit or crop out context.
- Never include passwords or the Wazuh admin password on screen.

## Retest record
If a test fails and is then fixed, keep **both** transcripts. Add a one-line note next to the failed one (`failed-<date>-reason.txt`): what failed, why, what changed, when it was retested. That is what an assessor expects to see.
