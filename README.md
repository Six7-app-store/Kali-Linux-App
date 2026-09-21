# Kali Linux Desktop App

Eine grafische Kali-Linux-Lernumgebung für Hochschulkurse zur IT-Sicherheit.
Jeder Studierende bekommt einen eigenen Zugang auf einer gemeinsamen Kali-VM und
arbeitet dort auf einem vollständigen XFCE-Desktop, den er per Remotedesktop
(RDP) erreicht — mit vorbereiteten Desktop-Verknüpfungen, kuratierten Werkzeugen
und einem Übungsverzeichnis.

> **Nur für autorisierte Übungen.** Die enthaltenen Werkzeuge dürfen
> ausschließlich auf Systemen eingesetzt werden, die der Dozent ausdrücklich
> freigegeben hat. Scans oder Angriffe auf fremde Systeme ohne Erlaubnis sind
> strafbar.

## Vorinstallierte Software

**Im Image (per Packer):**

- XFCE-Desktop mit XRDP (grafischer Zugang über Port 3389)
- Kali-Werkzeuge (`kali-linux-headless`) plus kuratierte Auswahl:
  nmap, wireshark, burpsuite, metasploit-framework, john, hydra, sqlmap,
  gobuster, dirb, nikto, aircrack-ng, netcat
- Desktop-Anwendungen: Firefox ESR, XFCE-Terminal, Thunar, Mousepad
- Wörterlisten unter `/usr/share/wordlists/`

**Beim ersten Boot (per cloud-init):**

- curl, wget, git, htop, nano, vim, net-tools

## Desktop-Integration

Jeder Nutzer startet in einer fertig eingerichteten Sitzung:

- **Desktop-Starter** für Terminal, Kurs-Übungen, Firefox, Wireshark und Burp Suite
- **Willkommensfenster** beim ersten Login mit der Kurzanleitung
- **Dateizuordnungen** (`.txt` → Mousepad, `.pcap` → Wireshark, `.html` → Firefox)
- **Kursverzeichnis** `~/kali-kurs/`:

```
~/kali-kurs/
├── LIES_MICH.txt              ← Kurzreferenz, Spielregeln, Werkzeugübersicht
└── uebungen/
    ├── 01-recon/
    ├── 02-portscan/
    ├── 03-traffic-analyse/
    ├── 04-web-schwachstellen/
    └── 05-passwoerter/
```

## User-Management

- **Ein Account pro Nutzer**, abgeleitet aus der E-Mail-Adresse
  (z. B. `alice.smith@dhbw.de` → Benutzername `alicesmith`)
- Alle Nutzer aller Teams landen auf **einer gemeinsamen VM**
- Jeder Nutzer erhält ein automatisch generiertes, zufälliges Passwort
- Login per Remotedesktop (RDP) oder SSH, jeweils mit Passwort

## VM-Deployment

| | |
|---|---|
| VMs gesamt | **1** (geteilt von allen Teams und Nutzern) |
| VMs pro Team | — |
| VMs pro Nutzer | — |
| Flavor | `gp1.medium` (größer als die Terminal-App wegen der Desktops) |
| Floating IP | Nein — Zugang über IPv6 (siehe „Verbinden") |

## Verbinden

Die VM ist ausschließlich über **IPv6** erreichbar (die feste IPv4 im
DHBWV6-Netz ist eine private NAT-Adresse). Zugang nur aus dem **Campusnetz oder
per VPN**.

**Windows (Remotedesktopverbindung):**

1. `mstsc` starten
2. Als Computer die IPv6-Adresse **in eckigen Klammern** mit Port eingeben:
   `[2001:7c0:…]:3389` — ohne die Klammern liest der Client den letzten `:` als
   Port-Trenner
3. Mit Benutzername und Passwort aus den Zugangsdaten anmelden

**Terminal (alternativ):** `ssh benutzername@2001:7c0:…`

## Konfigurierbare Variablen

| Variable | Beschreibung | Pflicht |
|---|---|---|
| `network_uuid` | UUID des internen Netzwerks | Ja |
| `shared_secgroup_id` | ID der gemeinsamen Security Group | Ja |
| `rdp_source_cidr` | IPv6-Präfix, das auf Port 3389 zugreifen darf | Nein |
| `floating_ip_pool` | Name des External Networks (derzeit ungenutzt) | Nein |

## Deployment-Dauer

| Schritt | Dauer (ca.) |
|---|---|
| Packer Image Build | 20–35 min |
| Terraform apply | 3–5 min |
| **Gesamt (Erstdeployment)** | **25–40 min** |

Bei Folge-Deployments (Image bereits gebaut) nur Terraform: **3–5 min**.
