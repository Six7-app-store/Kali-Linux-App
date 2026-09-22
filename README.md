# Kali Linux Desktop App

Kali-VM mit XFCE-Desktop und kuratierten Security-Werkzeugen für den OpenStack App Store.

## Features

- **XFCE-Desktop** per XRDP (Port 3389, über IPv6)
- **Kali-Werkzeuge:** nmap, wireshark, tcpdump, burpsuite, metasploit, john, hydra, sqlmap, gobuster, nikto, aircrack-ng
- **Desktop-Integration:** Starter, Autostart, Kursverzeichnis `~/kali-kurs/`
- **Multi-User:** Geteilte VM, pro Nutzer eigene RDP-Session + Account

## 0. Vorbedingung: Kali-Image hochladen

```bash
export OS_CLOUD=openstack  # Campusnetz oder VPN

# Image von cdimage.kali.org laden, dann:
openstack image create "Kali Linux 2025.3" \
  --disk-format qcow2 --container-format bare \
  --file kali-linux-2025.3-cloud-genericcloud-amd64.qcow2 \
  --property hw_qemu_guest_agent=yes --private
```

Der Image-Name muss mit `source_image_name` in `packer/variables.pkr.hcl` übereinstimmen.

## 1. Deployment

### Weg A: App Store

1. Credentials hinterlegen (App Store)
2. Git-URL + Release registrieren
3. Admin-Freigabe
4. Deployment starten

### Weg B: Manuell

```bash
# Image bauen
cd packer
packer init .
packer build -var image_name=kali-app-v1 .

# VM erzeugen
cd ../terraform
cat > meine.auto.tfvars <<'EOF'
image_name = "kali-app-v1"
users = {
  "Team 1" = [
    { email = "vorname.nachname@dhbw.de" }
  ]
}
EOF

terraform init
terraform apply

# Zugangsdaten
terraform output -json user_accounts

# Validieren (cloud-init braucht nach dem apply noch ~3 Minuten)
export SSH_PASS="<passwort>"
../validate.sh <username> <ipv6-address>

# Verbinden
# Windows: mstsc -> [2001:7c0:...]:3389
# Linux:   ssh username@2001:7c0:...

# Aufräumen
terraform destroy
openstack image delete kali-app-v1
```

## 2. Aufbau

| Datei | Aufgabe |
|---|---|
| `packer/template.pkr.hcl` | Build-Definition, ruft die Steps auf |
| `packer/scripts/01-base.sh` | apt, debconf |
| `packer/scripts/02-desktop.sh` | XFCE, XRDP (IPv6-Binding) |
| `packer/scripts/03-tools.sh` | Kali-Werkzeuge |
| `packer/scripts/04-integration.sh` | Desktop-Starter, Kursverzeichnis |
| `packer/scripts/05-verify.sh` | Post-Build-Checks + Image-Hygiene |
| `terraform/main.tf` | VM + Security Group + User-Ableitung |
| `terraform/cloud-init-multi-user.yml.tpl` | Erster Boot |
| `terraform/outputs.tf` | Zugangsdaten (Contract) |
| `validate.sh` | Post-Deployment-Test |

**Ablauf:** Packer baut das Image → Terraform erzeugt die VM → cloud-init legt Nutzer an und startet die Dienste.

Die Steps werden von Packer selbst der Reihe nach hochgeladen und ausgeführt (`scripts = [...]` in `template.pkr.hcl`). Einen Orchestrator auf der Build-VM gibt es bewusst nicht: Packer lädt nur die dort genannten Dateien hoch, ein Skript, das andere aufruft, fände sie nicht vor.

## 3. VM-Deployment

| | |
|---|---|
| VMs | 1 (geteilt) |
| Flavor | gp1.medium |
| Netz | IPv6 (DHBWV6) |
| RDP-Port | 3389 (eigene Security Group) |

Es gibt **keine Floating IP**: sie ließe sich anlegen, aber nicht zuweisen, weil zwischen VM-Subnetz und externem Netz der Router fehlt. Die feste IPv4 ist eine private NAT-Adresse — erreichbar ist die VM nur über IPv6.

## 4. Konfigurierbare Variablen

| Variable | Beschreibung | Default |
|---|---|---|
| `image_name` | Glance-Image-Name (Pflicht) | — |
| `network_uuid` | Netzwerk-ID | 9b579624-… |
| `shared_secgroup_id` | Security Group | 7ca4f889-… |
| `rdp_source_cidr` | RDP-Quellpräfix (IPv6) | `::/0` |

`rdp_source_cidr` sollte auf das DHBW-Campuspräfix eingegrenzt werden — ein weltweit offener RDP-Port auf einer Kali-VM ist ein lohnendes Ziel.

## 5. Anpassungen

- **Werkzeuge:** `packer/scripts/03-tools.sh`
- **Dienste beim Boot:** `terraform/cloud-init-multi-user.yml.tpl`
- **Outputs:** Contract-Struktur in `outputs.tf` behalten, nur Werte ändern

Neue Build-Steps müssen in `template.pkr.hcl` in die `scripts`-Liste eingetragen werden, sonst werden sie nicht hochgeladen.

## 6. Was geprüft wird

| Ebene | Prüfung | Läuft wann |
|---|---|---|
| CI (`Shell`) | `bash -n`, jede Warnung ist ein Fehler | Jeder Push |
| CI (`Shell`) | `shellcheck --severity=warning` | Jeder Push |
| CI (`Shell`) | `04-integration.sh` gegen Wegwerf-Wurzel ausführen, Ergebnis prüfen | Jeder Push |
| CI (`Packer`/`Terraform`) | `fmt`, `validate`, `tflint`, `tfsec` | Jeder Push |
| Build | `05-verify.sh`: Programme, XRDP-IPv6-Konfiguration, Kursinhalte | Im Image-Build |
| Plan | Precondition gegen doppelte Benutzernamen | `terraform plan` |
| Boot | cloud-init prüft SSH/XRDP aktiv **und** Port 3389 auf IPv6 | Erster Boot |
| Deployment | `validate.sh` über SSH | Manuell |

Geprüft wird, wo möglich, Funktion statt Existenz. Hintergrund: ein unterminiertes Here-Document hat den Skriptquelltext in eine Kursdatei geschrieben und 25 Zeilen nie ausgeführt — `set -e`, der `ERR`-trap und alle Existenz-Checks blieben grün, weil die Datei ja da war.

## Spielregeln (für Studierende)

Diese Werkzeuge dürfen **nur auf freigegebenen Zielen** eingesetzt werden:

- Diese VM selbst
- Vom Dozenten freigegebene Übungs-Umgebung
- scanme.nmap.org

**Scans/Angriffe auf fremde Systeme ohne Erlaubnis sind strafbar** (§ 202a-c StGB).

## Bekannte Einschränkungen

- Die Passwörter stehen im Klartext in `user_data` und sind auf der VM über den Metadaten-Dienst lesbar (`curl http://169.254.169.254/openstack/latest/user_data`). Auf einer geteilten VM heißt das: jede:r sieht die Passwörter der anderen. Da alle Accounts ohnehin `sudo` haben, ändert das die Vertrauensgrenze nicht — für eine Kurs-VM akzeptabel, für Produktivbetrieb nicht.
- Dieselbe Person darf nur in **einem** Team stehen. Sonst bricht `terraform plan` mit einer Meldung über doppelte Benutzernamen ab.

---

**Fehlersuche:** siehe [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
