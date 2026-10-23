# CUI Enclave Lab: a segmented Windows/AD/PKI/SIEM/GRC build on Hyper-V

A reproducible home lab that builds a small, **fictional** CUI enclave and measures it against **NIST SP 800-171 Rev 2** (the basis of CMMC Level 2). Everything is scripted in PowerShell or documented step by step, so the environment can be rebuilt and the evidence regenerated.

> **Scope and honesty note.** This is a readiness exercise on mock data. It is not a certification, an official assessment, or a claim of CMMC compliance. No real CUI and nothing from any employer is used anywhere. Control mappings should be verified against the official publication before being relied on elsewhere.

## What it builds

| Layer | Implementation |
|---|---|
| Host | Single Hyper-V host, seven virtual switches (WAN/NAT, Corp, CUI, DMZ, Admin, Attack, Isolated) |
| Boundary | OPNsense firewall, default deny between segments, every rule logged and forwarded to the SIEM |
| Identity | Two domain controllers, tiered admin OU model (Tier 0/1/2), group-based access, baseline GPO, password and lockout policy |
| PKI | Offline root CA on an isolated switch plus an enterprise issuing CA publishing CRL/AIA over HTTP |
| Monitoring | Wazuh all-in-one SIEM, agents on Windows systems, firewall syslog, file-integrity monitoring on the CUI share |
| CUI enclave | File server with SMB signing and encryption required, NTFS permissions by group, file-access auditing; enclave workstation with no internet egress |
| GRC | CISO Assistant (Docker) holding assets, applied controls, evidence links and an NIST 800-171 audit |
| Evidence | A collector script that gathers artifacts and SHA-256 hashes them; a checklist mapping each artifact to requirements |

## Network design

| Segment | Subnet | Purpose |
|---|---|---|
| WAN | 192.168.100.0/24 | NAT to the internet |
| Corp | 10.20.0.0/24 | Standard users, used to prove an unauthorized user is denied |
| CUI | 10.30.0.0/24 | Enclave: file server and workstation, no internet egress |
| DMZ | 10.40.0.0/24 | GRC platform, restricted outbound |
| Admin | 10.50.0.0/24 | Domain controllers, PKI, SIEM |
| Attack | 10.60.0.0/24 | Adversary simulation (planned) |
| Isolated | none | Offline root CA only |

The allow-rule matrix and the alias/rule build are in [`docs/01-opnsense.md`](docs/01-opnsense.md) and [`docs/02-opnsense-rules.md`](docs/02-opnsense-rules.md).

## Build order

| Phase | What | Script or doc |
|---|---|---|
| 0 | Host prep: folders, Hyper-V defaults, switches | `scripts/00-Initialize-Host.ps1` |
| 1 | Firewall VM | `scripts/01-Build-Firewall.ps1`, `docs/01-opnsense.md` |
| 2 | VM shells from a manifest | `scripts/02-New-LabVMs.ps1`, `scripts/LabVMs.psd1` |
| 3 | Domain controllers, AD structure, GPO | `scripts/03-*.ps1`, `scripts/04-AD-Structure.ps1` |
| 4 | Offline root and issuing CA | `scripts/05-*.ps1` to `07-*.ps1` |
| 5 | Evidence collector | `scripts/08-Collect-Evidence.ps1` |
| 6 | SIEM agents, domain join, file server, users | `scripts/09-*.ps1` to `12-*.ps1` |
| 7 | Access tests run as the intended user | `scripts/13-Access-Tests.ps1` |
| 8 | GRC platform, assets, assessment | `docs/04-*.md` to `docs/06-*.md` |

Shared helpers live in `scripts/LabCommon.ps1`. Passwords are always prompted for with `Read-Host -AsSecureString` and are never written to disk.

## Status

Done: network, firewall rules, domain and tiered OUs, two-tier PKI, Wazuh with agents, CUI file server with audited, encrypted SMB, scripted access tests, GRC platform with assets and frameworks loaded.

In progress: completing the NIST 800-171 assessment (`docs/06-assessment-worksheet.md`), POA&M modelling, remaining screenshots.

Planned: certificate autoenrollment, tiered logon-restriction GPOs, MFA evaluation, log retention policy, ATK01 adversary simulation with Wazuh detection tests, and an AI governance lab (Ollama, garak, PyRIT, promptfoo mapped to NIST AI RMF and ISO 42001).

## Known temporary exceptions (tracked as POA&M items)

An Admin-segment allow-all rule used during build, a temporary DMZ web rule for package downloads, a host-based management route with WAN rules, and a Corp-to-file-server SMB rule kept for access testing (blocked by file permissions).

## Lessons learned

- The OPNsense DVD ISO is BIOS-only, so the firewall VM must be Generation 1.
- Root CA setup fails with `ERROR_NETNAME_DELETED` unless the VM has a NIC, so give it one on an isolated switch.
- The Hyper-V basic console cannot paste; drive VMs with `Copy-VMFile` scripts or SSH.
- Windows 11 VMs need a process-scope execution policy to run the scripts.
- Run each access test as the intended user, or the result proves nothing.

## Disclaimer

For education and lab use. Review every script before running it, and do not point it at systems you do not own.
