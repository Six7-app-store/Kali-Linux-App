# Kali Linux Desktop App

Kali-VM mit XFCE-Desktop und curatierten Security-Werkzeugen für OpenStack App Store.

## Features

- **XFCE-Desktop** per XRDP (Port 3389, über IPv6)
- **Kali-Werkzeuge:** nmap, wireshark, burpsuite, metasploit, john, hydra, sqlmap, gobuster, nikto, aircrack-ng
- **Desktop-Integration:** Starter, Autostart, Kursverzeichnis `~/kali-kurs/`
- **Multi-User:** Geteilte VM, pro Nutzer eigene RDP-Session + Account
- **Robust:** Error-Handling, Post-Build/Post-Deployment-Tests

## Quickstart

**Vorbedingung:** Kali-Cloud-Image nach OpenStack hochladen (siehe `ANLEITUNG.md` §0)

```bash
# Image bauen
cd packer
packer init .
packer build -var image_name=kali-app-v1 .

# VM erzeugen
cd ../terraform
cat > meine.auto.tfvars <<EOF
image_name = "kali-app-v1"
users = { "Team" = [{ email = "student@dhbw.de" }] }
EOF

terraform apply

# Zugangsdaten
terraform output user_accounts

# Validieren
export SSH_PASS="<passwort>"
../validate.sh <username> <ipv6-address>

# Verbinden
# Windows: mstsc -> [2001:7c0:...]:3389
# Linux: ssh username@2001:7c0:...
```

## VM-Deployment

| | |
|---|---|
| VMs | 1 (geteilt) |
| Flavor | gp1.medium |
| Netz | IPv6 (DHBWV6) |
| RDP-Port | 3389 (neue Security Group) |

## Konfigurierbare Variablen

| Variable | Beschreibung | Default |
|---|---|---|
| `network_uuid` | Netzwerk-ID | 9b579624-... |
| `shared_secgroup_id` | Security Group | 7ca4f889-... |
| `rdp_source_cidr` | RDP-Quellpräfix (IPv6) | ::/0 |
| `floating_ip_pool` | External Network | DHBW (ungenutzt) |

## Dokumentation

- **ANLEITUNG.md:** Deployment-Anleitung (manuell + App Store)
- **TROUBLESHOOTING.md:** Fehlerbehandlung
- **packer/scripts/0{1-5}.sh:** Build-Steps (gut strukturiert)
- **terraform/:** Infrastruktur (HCL)
- **validate.sh:** Post-Deployment-Test

## Architektur

**Build-Zeit:**
1. `01-base.sh` — apt, debconf
2. `02-desktop.sh` — XFCE, XRDP (IPv6-Binding!)
3. `03-tools.sh` — Kali-Werkzeuge
4. `04-integration.sh` — Desktop-Starter, Kursverzeichnis
5. `05-verify.sh` — Post-Build-Checks

**Deploy-Zeit (cloud-init):**
- Nutzer + Gruppen anlegen
- Firewall konfigurieren (SSH 22, RDP 3389)
- Services starten + prüfen

## Spielregeln (für Studierende)

Diese Werkzeuge dürfen **nur auf freigegebenen Zielen** eingesetzt werden:
- Diese VM selbst
- Vom Dozenten freigegebene Übungs-Umgebung
- scanme.nmap.org

**Scans/Angriffe auf fremde Systeme ohne Erlaubnis sind strafbar** (§ 202a-c StGB).

---

**Supportdokumentation:** Siehe `ANLEITUNG.md` und `TROUBLESHOOTING.md`
