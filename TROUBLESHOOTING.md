# Troubleshooting

## Packer-Build fehlgeschlagen

### Basis-Image (Debian → Kali)

**„No image was found matching filters: … Name:Kali Linux …"**
→ Es wurde eine alte Version deployt (bis `v1.2.0`). Im App Store die neueste Version auswählen.
Im Log muss eine neue `Commit:`-ID stehen.

**„No image was found matching filters: … Name:Debian …"**
→ Das Image heißt in eurem OpenStack anders oder wurde umbenannt. Im Deploy-Formular bei
`source_image_name` das Debian-Image aus der Liste wählen.

**„ssh: unable to authenticate, attempted methods [none publickey]"**
→ Packer hat sich mit dem Standardbenutzer des Images angemeldet, den es dort nicht gibt. Das war
der alte Stand mit `ssh_username = "debian"`. Der aktuelle Stand legt per `user_data` einen eigenen
Build-Benutzer `packer` an. Prüfen, ob die neueste Version deployt wurde.

**„SSH timeout" trotz Build-Benutzer `packer`**
→ cloud-init läuft im Basis-Image nicht oder ignoriert `user_data`. Dann wurde der Benutzer nie
angelegt. Bei den Admins nachfragen, ob das Image cloud-init enthält.

**Ein hängender Build lässt sich im App Store nicht abbrechen**
→ Nicht nötig: Packer gibt nach `ssh_timeout` (20 min) auf und löscht die temporäre VM und das
Schlüsselpaar selbst.

**„Nur … GB frei auf /, mindestens 15 GB nötig"**
→ Root-Disk des Build-Flavors ist zu klein für Desktop + Werkzeuge. In `template.pkr.hcl` einen
Flavor mit größerer Disk wählen.

**„Kali-Keyring enthält den erwarteten Schlüssel … nicht"**
→ Kali hat den Archiv-Signierschlüssel gewechselt (zuletzt April 2025), oder der Download war
manipuliert. Neuen Fingerprint **nur aus offizieller Quelle** (kali.org-Blog) übernehmen und
`KALI_FINGERPRINT` in `01-base.sh` anpassen.

**„Umstellung unvollständig: /etc/os-release meldet nicht ID=kali"**
→ `full-upgrade` auf kali-rolling ist nicht vollständig durchgelaufen. Im Packer-Log nach dem
ersten `E:` von apt suchen. Häufigste Ursache: ein Kali-Mirror ist kurz nicht erreichbar, dann den
Build neu starten.

### Allgemein

**„SSH timeout"**
→ Build-Flavor zu klein oder Startup dauert länger.
→ `template.pkr.hcl`: `ssh_timeout = "30m"` erhöhen.

**„Permission denied"**
→ Credentials falsch. `export OS_CLOUD=openstack` prüfen.
→ `openstack quota list` testen.

**„Permission denied" *innerhalb* eines Build-Steps (apt, sed, /etc/…)**
→ `execute_command = "sudo -E bash '{{.Path}}'"` fehlt in `template.pkr.hcl`.
Der Shell-Provisioner läuft sonst als SSH-Benutzer `packer`, nicht als root.

**„No such file or directory" beim Aufruf eines Steps**
→ Das Skript steht nicht in der `scripts`-Liste in `template.pkr.hcl`. Packer
lädt ausschließlich die dort genannten Dateien auf die Build-VM hoch.

**Ein Step bricht ab**
→ Logs im Packer-Output prüfen.
→ Lokal nachstellen: `bash -n packer/scripts/0X-*.sh` und `shellcheck packer/scripts/*.sh`.

## Shell-Skripte: stille Fehler

**Eine Datei wird angelegt, enthält aber Skriptquelltext**
→ Unterminiertes Here-Document: der Schluss-Marker ist vertippt (`KRUS` statt
`KURS`). Alles bis Dateiende landet in der Datei, die restlichen Zeilen laufen
nie. Weder `set -e` noch der `ERR`-trap schlagen an, weil `cat` erfolgreich ist.
→ `bash -n datei.sh` meldet es — aber nur als **Warnung auf stderr mit
Exit-Code 0**. Der `Shell`-Workflow wertet deshalb jede Ausgabe als Fehler.

**Eine `sed -i`-Ersetzung passiert nicht**
→ `sed` meldet auch ohne Treffer Erfolg. Ein `sed … || fallback` läuft deshalb
nie in den Fallback. Nach dem Schreiben mit `grep -qxF` gegenprüfen (so macht es
`set_ini_key` in `02-desktop.sh`).

**Ein Glob im Ziel einer Umleitung greift nicht**
→ `> "verzeichnis/0$i-*/datei.txt"` wird in Anführungszeichen nicht expandiert.
Namen ausschreiben statt globben.

**Ein Remote-Check prüft die falsche Maschine**
→ In `ssh host "… $(befehl) …"` expandiert `$(…)` **lokal**. Remote-Befehle
gehören in einfache Anführungszeichen.

## Terraform apply fehlgeschlagen

**„missing required variable"**
→ `image_name` in `meine.auto.tfvars` stimmt nicht mit dem Packer-Output überein.

**„Roster ergibt doppelte Linux-Benutzernamen"**
→ Dieselbe Person steht in zwei Teams, oder zwei Adressen bilden auf denselben
Namen ab. Roster bereinigen — sonst teilten sich zwei Studierende einen Account
und das zweite Passwort überschriebe das erste.

**„Security group not found"**
→ SG-UUID in `variables.tf` existiert nicht.
→ `openstack security group list` prüfen.

**„template rendering failed"**
→ YAML-Syntax in `cloud-init-multi-user.yml.tpl` kaputt.
→ `terraform console` → manuell rendern + YAML-Parser testen.
→ Achtung: `${…}` ist Terraform-Interpolation. In Shell-Zeilen innerhalb der
Vorlage nur `$(…)` verwenden.

## VM oben, aber nicht erreichbar

**SSH-Verbindung fehlgeschlagen**
→ Nach dem `apply` noch ~3 Minuten warten (cloud-init läuft).
→ `validate.sh` gibt genauere Fehlermeldungen.

**XRDP nicht aktiv**
```bash
ssh user@ipv6
sudo systemctl status xrdp
sudo journalctl -u xrdp -n 50
sudo systemctl restart xrdp
```

**RDP-Client verbindet nicht, XRDP läuft aber**
```bash
# Lauscht er auf IPv6? Erwartet wird [::]:3389, nicht 0.0.0.0:3389
ss -tln | grep 3389
grep -E '^(port|enable_ipv6)=' /etc/xrdp/xrdp.ini
```
→ Erwartet: `port=tcp6://:3389` und `enable_ipv6=true`.
→ Im Client die IPv6-Adresse in eckigen Klammern angeben: `[2001:7c0:…]:3389`.

**Port 3389 von außen dicht**
→ Es gibt keine Host-Firewall (kein ufw). Gefiltert wird über OpenStack
Security Groups:
```bash
openstack security group list
openstack security group rule list kali-user-rdp
```
→ Die Regel muss `ethertype = IPv6` haben; eine IPv4-Regel ist hier wirkungslos.

**Nutzer wurden nicht angelegt**
```bash
sudo cat /var/log/setup-complete.log
sudo cat /var/log/cloud-init-output.log
```

## Idempotenz testen

```bash
terraform plan   # sollte "No changes" zeigen
terraform apply
```

Zeigt es Änderungen → Fehler in HCL oder Terraform-State.

## Post-Deployment-Checks

```bash
export SSH_PASS="<passwort>"
./validate.sh <user> <ipv6>
```

Gibt pro Dienst, Werkzeug und Kursdatei einen eigenen Fehler aus. Braucht
`sshpass`.
