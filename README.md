# Kali Linux Desktop App

Kali-VM mit XFCE-Desktop und kuratierten Security-Werkzeugen für den OpenStack App Store.
Bereitgestellt mit **OpenTofu**, ohne Image-Build.

## Features

- **XFCE-Desktop** per XRDP (Port 3389, über IPv6)
- **Kali-Werkzeuge:** nmap, wireshark, tcpdump, burpsuite, metasploit, john, hydra, sqlmap, gobuster, nikto, aircrack-ng
- **Desktop-Integration:** Starter, Autostart, Kursverzeichnis `~/kali-kurs/`
- **Multi-User:** Geteilte VM, pro Nutzer eigene RDP-Session + Account

## 0. So entsteht die VM

Es gibt keinen Image-Build (kein Packer) und kein Kali-Image in OpenStack. Images können nur die
Cloud-Admins hinzufügen.

1. OpenTofu startet die VM aus dem vorhandenen Image **„Debian 13“** (`source_image_name`).
2. Beim **ersten Start** führt cloud-init `terraform/scripts/setup.sh` aus. Das Skript stellt
   Debian vollständig auf **Kali (kali-rolling)** um und installiert Desktop, Werkzeuge und
   Kursmaterial.
3. Ist alles durchgelaufen, startet die VM einmal neu und ist bereit.

**Wichtig: Die VM ist nicht sofort nutzbar.** `tofu apply` ist fertig, sobald die VM läuft. Die
Einrichtung danach lädt mehrere GB und dauert deutlich länger. Bewusst wartet `apply` **nicht**
darauf, weil der App-Store-worker `apply` nach 30 Minuten abbricht. Den Stand sieht man so:

| Wo | Was |
|---|---|
| SSH-Login (`/etc/motd`) | ⏳ läuft noch / ✅ bereit / ❌ fehlgeschlagen |
| `/var/log/kali-app-setup.log` | vollständiges Protokoll, lesbar für alle Accounts |
| `/var/lib/kali-app/ready` | existiert genau dann, wenn alles durchlief |
| `validate.sh` | zeigt zuerst den Stand der Einrichtung |

SSH funktioniert schon während der Einrichtung, RDP erst danach.

Voraussetzungen: Die VM braucht Internetzugang zu `archive.kali.org` und `http.kali.org`, und
mindestens **15 GB** freien Plattenplatz (`01-base.sh` prüft das vorab).

## 1. Deployment

### Weg A: App Store

1. Credentials hinterlegen (App Store)
2. Git-URL registrieren, Release-Tag anlegen (der App Store zeigt Tags als Versionen)
3. Admin-Freigabe
4. Deployment starten, Version wählen

Nach jedem Merge nach `main` braucht es ein **neues Tag**, sonst sieht der App Store die Änderung
nicht. Ein Tag zeigt fest auf einen Commit und wandert nicht mit `main` mit.

### Weg B: Manuell

```bash
cd terraform
cat > meine.auto.tfvars <<'EOF'
users = {
  "Team 1" = [
    { email = "vorname.nachname@dhbw.de" }
  ]
}
EOF

tofu init
tofu apply

# Zugangsdaten
tofu output -json user_accounts

# Stand der Einrichtung + Validierung
export SSH_PASS="<passwort>"
../validate.sh <username> <ipv6-address>

# Verbinden (wenn validate.sh grün ist)
# Windows: mstsc -> [2001:7c0:...]:3389
# Linux:   ssh username@2001:7c0:...

# Aufräumen
tofu destroy
```

## 2. Aufbau

| Datei | Aufgabe |
|---|---|
| `terraform/main.tf` | VM + Security Group + User-Ableitung, liefert `scripts/` mit aus |
| `terraform/cloud-init-multi-user.yml.tpl` | Accounts, Skripte, Start von `setup.sh`, Neustart |
| `terraform/scripts/setup.sh` | Führt alle `NN-*.sh` der Reihe nach aus, Status in motd/Log |
| `terraform/scripts/01-base.sh` | Debian → Kali umstellen, debconf, Basispakete |
| `terraform/scripts/02-desktop.sh` | XFCE, XRDP (IPv6-Binding) |
| `terraform/scripts/03-tools.sh` | Kali-Werkzeuge |
| `terraform/scripts/04-integration.sh` | Desktop-Starter, Kursverzeichnis in `/etc/skel` |
| `terraform/scripts/05-users.sh` | Kursmaterial in die bereits angelegten Accounts, Gruppe `wireshark` |
| `terraform/scripts/06-verify.sh` | Checks: Kali, Programme, XRDP-IPv6, Kursinhalte |
| `terraform/outputs.tf` | Zugangsdaten (Contract) |
| `validate.sh` | Test nach dem Deployment |

Der Ordner heißt weiter `terraform/`, OpenTofu liest dieselben `.tf`-Dateien.

`main.tf` liefert **jedes** `*.sh` aus `scripts/` aus (gzip+base64 in der `user_data`, Limit
64 KB), und `setup.sh` führt jedes `NN-*.sh` in Namensreihenfolge aus. Ein neuer Schritt braucht
nur eine neue Datei mit Nummernpräfix. Eine Liste, die man vergessen kann, gibt es nicht.

`05-users.sh` gibt es, weil cloud-init die Accounts **vor** der Einrichtung anlegt. Zu diesem
Zeitpunkt ist `/etc/skel` noch leer, und `useradd` kopiert es nur beim Anlegen.

## 3. VM-Deployment

| | |
|---|---|
| VMs | 1 (geteilt) |
| Basis-Image | „Debian 13“, im Formular als `source_image_name` wählbar |
| Flavor | win11.medium (2 vCPU, 8 GB RAM, 80 GB). `gp1` hat nur 10 GB Platte, zu wenig für Kali mit Desktop. Im Formular als `flavor` wählbar. |
| Netz | IPv6 (DHBWV6) |
| RDP-Port | 3389 (eigene Security Group) |

Es gibt **keine Floating IP**: sie ließe sich anlegen, aber nicht zuweisen, weil zwischen VM-Subnetz und externem Netz der Router fehlt. Die feste IPv4 ist eine private NAT-Adresse — erreichbar ist die VM nur über IPv6.

## 4. Konfigurierbare Variablen

| Variable | Beschreibung | Default |
|---|---|---|
| `source_image_name` | Debian-Basis-Image | `Debian 13` |
| `flavor` | Flavor der VM (mind. 20 GB Platte) | `win11.medium` |
| `network_uuid` | Netzwerk-ID | 9b579624-… |
| `shared_secgroup_id` | Security Group | 7ca4f889-… |
| `rdp_source_cidr` | RDP-Quellpräfix (IPv6) | `::/0` |

`rdp_source_cidr` sollte auf das DHBW-Campuspräfix eingegrenzt werden — ein weltweit offener RDP-Port auf einer Kali-VM ist ein lohnendes Ziel.

## 5. Anpassungen

- **Werkzeuge:** `terraform/scripts/03-tools.sh`
- **Neuer Einrichtungsschritt:** neue Datei `terraform/scripts/NN-name.sh`. Ohne Nummernpräfix läuft
  sie nie, das prüft die CI.
- **Outputs:** Contract-Struktur in `outputs.tf` behalten, nur Werte ändern

## 6. Was geprüft wird

| Ebene | Prüfung | Läuft wann |
|---|---|---|
| CI (`Shell`) | Einrichtungsschritte heißen `NN-*.sh` | Jeder Push |
| CI (`Shell`) | `bash -n`, jede Warnung ist ein Fehler | Jeder Push |
| CI (`Shell`) | `shellcheck --severity=warning` | Jeder Push |
| CI (`Shell`) | `04-integration.sh` gegen Wegwerf-Wurzel ausführen, Ergebnis prüfen | Jeder Push |
| CI (`OpenTofu`) | `tofu fmt`, `tofu validate`, `tflint`, `tfsec` | Jeder Push |
| Plan | Precondition gegen doppelte Benutzernamen | `tofu plan` |
| Erster Start | `06-verify.sh`: Kali, Programme, XRDP-IPv6-Konfiguration, Kursinhalte | Auf der VM |
| Erster Start | `setup.sh`: SSH/XRDP aktiv **und** Port 3389 auf IPv6 | Auf der VM |
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
- Dieselbe Person darf nur in **einem** Team stehen. Sonst bricht `tofu plan` mit einer Meldung über doppelte Benutzernamen ab.
- Jede neue VM lädt Kali und alle Werkzeuge beim ersten Start neu herunter. Mit einem Image-Build
  passierte das einmal pro Version.

---

**Fehlersuche:** siehe [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
