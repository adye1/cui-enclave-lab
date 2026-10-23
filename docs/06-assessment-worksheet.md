# NIST SP 800-171 Rev 2: assessment worksheet (starter set)

Use with the compliance assessment `NIST 800-171 r2 - Enclave baseline` in CISO Assistant.
Evidence numbers refer to `03-evidence-checklist.md`. Short wording of each requirement is paraphrased; the tool shows the official text.

**Rules for filling this in**
- A result is only "compliant" if the evidence in the right-hand column proves it. Otherwise choose partially compliant or not implemented.
- Every gap goes in the observation and becomes a POA&M item.
- This is a lab readiness exercise with fictional data. Do not describe it as a certification or an official assessment.
- Verify the "check first" notes before marking a requirement compliant.

| Req. | Requirement (short) | Suggested result | Observation (paste and adapt) | Evidence | Check first / gap |
|---|---|---|---|---|---|
| 3.1.1 | Limit access to authorized users, processes, devices | Partially compliant | Access to CUI requires a domain account in CUI-Users; share and NTFS permissions are group-based. Tested allowed (cui.user1) and denied (corp.user1). | 5, 6, 7 | Gap: no device authentication (no NAC or 802.1X), so device authorization is not enforced. POA&M. |
| 3.1.2 | Limit access to permitted transactions and functions | Partially compliant | NTFS permissions limit CUI-Users to Modify and CUI-Admins to Full control; Corp users denied. | 6, 7 | Gap: no application-level function restriction; relies on file permissions only. |
| 3.1.5 | Least privilege, including privileged accounts | Partially compliant | Separate admin and standard accounts (t0-adam / adam); Tier 0 admin is in Protected Users; OU tier model defined. | 7 | Gap: tier logon-restriction GPOs are not yet implemented. POA&M. |
| 3.1.8 | Limit unsuccessful logon attempts | Compliant | Domain policy locks accounts after 5 failed attempts for 15 minutes. | 8 | Confirm with `Get-ADDefaultDomainPasswordPolicy` before marking. |
| 3.1.9 | Privacy and security notices | Compliant (lab wording) | LAB-Baseline-Security GPO shows a login banner on systems in the CUI-Enclave and Tier0 OUs. | 9 | Verify on WS01. The banner text is lab text, not the approved CUI banner. |
| 3.1.10 | Session lock after inactivity | Compliant | The same GPO sets a 15-minute inactivity lock (InactivityTimeoutSecs = 900). | 9 | Verify with `gpresult /r` on WS01 that the GPO applied. |
| 3.3.1 | Create and retain audit logs | Partially compliant | Audit policy enabled on FS01 (File System, File Share, Logon); events collected by Wazuh agents; firewall syslog forwarded. | 11, 12, 14 | Gap: log retention period not defined or configured. POA&M. |
| 3.3.2 | Trace actions to individual users | Compliant | Unique named accounts; Wazuh events show the acting user (cui.user1 success, corp.user1 denied). | 12 | Needs the Wazuh screenshots (checklist items 12). |
| 3.5.3 | Multifactor authentication | Not implemented | No MFA on local or network access to the lab systems. | none | POA&M: evaluate MFA for privileged and CUI access. |
| 3.5.7 | Minimum password complexity | Compliant | Domain policy: 14 characters minimum, complexity on. | 8 | Confirm in `ad-password-policy.txt`. |
| 3.5.8 | Prohibit password reuse | Compliant | Password history of 24 generations. | 8 | Confirm in `ad-password-policy.txt`. |
| 3.13.1 | Monitor and control communications at boundaries | Compliant | FW01 enforces a default-deny rule set between segments; rule hits are logged and forwarded to the SIEM. Allowed and blocked paths tested. | 1, 2, 3, 4, 14 | Needs the OPNsense screenshots. |
| 3.13.6 | Deny by default, allow by exception | Partially compliant | Default deny on every segment, allow rules are explicit and logged. | 1, 2, 4 | Gap: temporary allow-all rule on the Admin segment and a temporary DMZ web rule. Remove or restrict, then re-mark. |
| 3.13.8 | Cryptographic protection of CUI in transit | Partially compliant | SMB signing and encryption required on FS01 (SMB1 disabled). | 10 | Gap: other protocols in the enclave are not all encrypted (for example LDAP signing and TLS settings not verified). |
| 3.13.11 | FIPS-validated cryptography | Not implemented | FIPS mode is not enabled on lab systems. | none | POA&M: enable and assess FIPS mode where required. |
| 3.14.6 | Monitor systems and traffic for attacks | Partially compliant | Wazuh agents on all lab Windows systems; firewall events forwarded; file-integrity monitoring on the CUI share. | 12, 13, 14 | Gap: no tested detections yet (adversary simulation with ATK01 is planned). |
| 3.14.7 | Identify unauthorized use | Partially compliant | Failed access and logon events recorded and reviewable in Wazuh. | 12 | Gap: no alerting rules tuned for this yet. |
| 3.4.1 | Baseline configurations | Partially compliant | Build scripts in version-controlled folder; VM checkpoints at named baselines. | 16 | Gap: no formal baseline document or change-control record. |
| 3.4.2 | Security configuration settings | Partially compliant | Settings enforced by GPO and scripts (password, lockout, banner, SMB). | 8, 9, 10 | Gap: no CIS or STIG benchmark applied or scanned. |

## Applied controls to create (Operations), with the requirements each one supports
| Control | Supports |
|---|---|
| Group-based access to the CUI share | 3.1.1, 3.1.2, 3.1.5 |
| Account lockout and password policy | 3.1.8, 3.5.7, 3.5.8 |
| Login banner and session lock (GPO) | 3.1.9, 3.1.10 |
| Centralized audit logging (Wazuh) | 3.3.1, 3.3.2, 3.14.6, 3.14.7 |
| Network segmentation with default deny (FW01) | 3.13.1, 3.13.6 |
| SMB signing and encryption | 3.13.8 |
| Baseline configuration (scripts, checkpoints) | 3.4.1, 3.4.2 |

## POA&M items that fall out of this worksheet
1. Device authorization for the enclave (3.1.1).
2. Tier logon-restriction GPOs (3.1.5).
3. Define and enforce log retention (3.3.1).
4. Multifactor authentication (3.5.3).
5. Remove the temporary Admin and DMZ firewall rules (3.13.6).
6. Verify encryption of other in-transit protocols (3.13.8).
7. FIPS-validated cryptography (3.13.11).
8. Tested detections with adversary simulation (3.14.6, 3.14.7).
9. Formal baseline and a hardening benchmark (3.4.1, 3.4.2).
