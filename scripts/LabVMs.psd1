# Lab VM manifest. Edit sizes here, not in the scripts.
# IsoPattern is matched against file names in F:\ISOs (newest match wins).
@{
  VMs = @(
    @{ Name='DC01';      OS='Windows'; MemoryGB=4;  vCPU=2; DiskGB=80;  Switch=@('Lab-Admin');  IsoPattern='*WS2025*';  Role='Domain controller (Tier 0)' }
    @{ Name='DC02';      OS='Windows'; MemoryGB=4;  vCPU=2; DiskGB=80;  Switch=@('Lab-Admin');  IsoPattern='*WS2025*';  Role='Domain controller (Tier 0)' }
    @{ Name='PKI-ROOT';  OS='Windows'; MemoryGB=2;  vCPU=2; DiskGB=60;  Switch=@('Lab-Isolated'); IsoPattern='*WS2025*'; Role='Offline root CA (isolated switch, no other VMs)' }
    @{ Name='PKI-ISS';   OS='Windows'; MemoryGB=4;  vCPU=2; DiskGB=80;  Switch=@('Lab-Admin');  IsoPattern='*WS2025*';  Role='Enterprise issuing CA' }
    @{ Name='SIEM01';    OS='Linux';   MemoryGB=12; vCPU=4; DiskGB=250; Switch=@('Lab-Admin');  IsoPattern='*ubuntu*24*';     Role='Wazuh manager, indexer, dashboard' }
    @{ Name='FS01';      OS='Windows'; MemoryGB=4;  vCPU=2; DiskGB=150; Switch=@('Lab-CUI');    IsoPattern='*WS2025*';  Role='CUI file server (mock data only)' }
    @{ Name='WS01';      OS='Windows'; MemoryGB=4;  vCPU=2; DiskGB=80;  Switch=@('Lab-CUI');    IsoPattern='*Win11*';       Role='CUI enclave workstation'; Tpm=$true }
    @{ Name='WS02';      OS='Windows'; MemoryGB=4;  vCPU=2; DiskGB=80;  Switch=@('Lab-Corp');   IsoPattern='*Win11*';       Role='Corporate workstation';   Tpm=$true }
    @{ Name='WS03';      OS='Windows'; MemoryGB=4;  vCPU=2; DiskGB=80;  Switch=@('Lab-Corp');   IsoPattern='*Win11*';       Role='Corporate workstation';   Tpm=$true }
    @{ Name='GRC01';     OS='Linux';   MemoryGB=8;  vCPU=2; DiskGB=100; Switch=@('Lab-DMZ');    IsoPattern='*ubuntu*24*';     Role='GRC platform (SSP, evidence, POA&M)' }
    @{ Name='ATK01';     OS='Linux';   MemoryGB=4;  vCPU=2; DiskGB=60;  Switch=@('Lab-Attack'); IsoPattern='*ubuntu*24*';     Role='Adversary simulation (Atomic Red Team, Caldera)' }
  )
}
