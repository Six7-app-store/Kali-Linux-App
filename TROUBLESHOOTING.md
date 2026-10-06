# Troubleshooting

## Wo nachsehen

Die Einrichtung läuft beim ersten Start **auf der VM**, nicht mehr in einem Build-Log des App
Stores. Per SSH (geht schon während der Einrichtung):

```bash
cat /etc/motd                              # ⏳ läuft / ✅ bereit / ❌ fehlgeschlagen
tail -f /var/log/kali-app-setup.log        # Fortschritt, lesbar für alle Accounts
grep -E '^===|❌|E:' /var/log/kali-app-setup.log   # Schritte und Fehler im Überblick
sudo cat /var/log/cloud-init-output.log    # alles, was cloud-init ausgegeben hat
cloud-init status --long                   # done / running / error
```

`validate.sh` zeigt den Stand der Einrichtung zuerst.

## `tofu apply` fehlgeschlagen

**„Value for undeclared variable"**
→ Der worker übergibt eine Variable, die `terraform/variables.tf` nicht kennt. `image_name` ist
deshalb noch als ungenutzte Variable deklariert. Für jede weitere: im worker entfernen oder genauso
deklarieren.

**„No image was found … Debian 13"**
→ Das Image heißt in eurem OpenStack anders. Im Deploy-Formular bei `source_image_name` das
Debian-Image aus der Liste wählen und den exakten Namen als Default in `terraform/variables.tf`
eintragen.

**„Roster ergibt doppelte Linux-Benutzernamen"**
→ Dieselbe Person steht in zwei Teams, oder zwei Adressen bilden auf denselben Namen ab. Roster
bereinigen, sonst teilten sich zwei Studierende einen Account und das zweite Passwort überschriebe
das erste.

**„Security group not found"**
→ SG-UUID in `variables.tf` existiert nicht (`openstack security group list`).

**„template rendering failed"**
→ YAML-Syntax in `cloud-init-multi-user.yml.tpl` kaputt. `tofu console` → manuell rendern.
→ Achtung: `${…}` ist OpenTofu-Interpolation. In Shell-Zeilen innerhalb der Vorlage nur `$(…)`.
Die Einrichtungsskripte liegen deshalb als eigene Dateien in `scripts/` und werden unverändert
(gzip+base64) mitgeschickt.

**user_data zu groß (Nova: > 65535 Bytes)**
→ Aktuell ca. 22 KB. Wächst `scripts/` stark, zuerst große Textblöcke (z. B. Kurstexte) prüfen.

## Einrichtung beim ersten Start fehlgeschlagen

**motd zeigt ❌ / `validate.sh` meldet „Einrichtung fehlgeschlagen"**
→ Im Log nach der ersten Zeile mit `❌` oder `E:` suchen. Davor steht `=== NN-name.sh ===`, also der
Schritt, der abgebrochen ist. Die VM bleibt für die Fehlersuche so stehen und startet nicht neu.

**„Nur … GB frei auf /, mindestens 15 GB nötig"**
→ Der Flavor hat zu wenig Platte. Alle `gp1`-Flavors haben nur 10 GB. Im Formular bei `flavor`
einen größeren wählen (Default `win11.medium`, 80 GB).

**„Kali-Keyring enthält den erwarteten Schlüssel … nicht"**
→ Kali hat den Archiv-Signierschlüssel gewechselt (zuletzt April 2025), oder der Download war
manipuliert. Neuen Fingerprint **nur aus offizieller Quelle** (kali.org-Blog) übernehmen und
`KALI_FINGERPRINT` in `scripts/01-base.sh` anpassen.

**„Umstellung unvollständig: /etc/os-release meldet nicht ID=kali"**
→ `full-upgrade` auf kali-rolling ist nicht vollständig durchgelaufen. Im Log nach dem ersten `E:`
von apt suchen. Häufigste Ursache: ein Kali-Mirror war kurz nicht erreichbar. Dann die VM neu
deployen.

**„Could not get lock /var/lib/dpkg/lock-frontend"**
→ apt-daily lief beim ersten Start parallel länger als 10 Minuten (`DPkg::Lock::Timeout` in
`01-base.sh`). Selten, dann neu deployen.

**Account ohne `kali-kurs` oder Desktop-Starter**
→ `05-users.sh` ist nicht gelaufen oder abgebrochen. cloud-init legt die Accounts **vor** der
Einrichtung an. Das Kursmaterial kommt erst durch `05-users.sh` in die Home-Verzeichnisse.

## Einrichtung läuft „ewig"

**motd zeigt nach langer Zeit noch ⏳**
→ `tail -f /var/log/kali-app-setup.log`: Bewegt sich etwas, lädt es noch Pakete (mehrere GB).
Steht es seit langem still, `cloud-init status --long` prüfen.
→ `apply` ist davon unabhängig. Es endet, sobald die VM läuft, und wartet absichtlich nicht auf
die Einrichtung, weil der worker `apply` nach 30 Minuten abbricht.

## Shell-Skripte: stille Fehler

**Eine Datei wird angelegt, enthält aber Skriptquelltext**
→ Unterminiertes Here-Document: der Schluss-Marker ist vertippt (`KRUS` statt `KURS`). Alles bis
Dateiende landet in der Datei, die restlichen Zeilen laufen nie. Weder `set -e` noch der
`ERR`-trap schlagen an, weil `cat` erfolgreich ist.
→ `bash -n datei.sh` meldet es — aber nur als **Warnung auf stderr mit Exit-Code 0**. Der
`Shell`-Workflow wertet deshalb jede Ausgabe als Fehler.

**Ein neuer Einrichtungsschritt läuft nie**
→ Er heißt nicht `NN-*.sh`. `setup.sh` führt nur Dateien mit zweistelligem Nummernpräfix aus.
Die CI prüft das.

**Eine `sed -i`-Ersetzung passiert nicht**
→ `sed` meldet auch ohne Treffer Erfolg. Ein `sed … || fallback` läuft deshalb nie in den
Fallback. Nach dem Schreiben mit `grep -qxF` gegenprüfen (so macht es `set_ini_key` in
`02-desktop.sh`).

**Ein Glob im Ziel einer Umleitung greift nicht**
→ `> "verzeichnis/0$i-*/datei.txt"` wird in Anführungszeichen nicht expandiert. Namen ausschreiben
statt globben.

**Ein Remote-Check prüft die falsche Maschine**
→ In `ssh host "… $(befehl) …"` expandiert `$(…)` **lokal**. Remote-Befehle gehören in einfache
Anführungszeichen.

## VM fertig eingerichtet, aber nicht erreichbar

**XRDP nicht aktiv**
```bash
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
→ Es gibt keine Host-Firewall (kein ufw). Gefiltert wird über OpenStack Security Groups:
```bash
openstack security group list
openstack security group rule list kali-user-rdp
```
→ Die Regel muss `ethertype = IPv6` haben; eine IPv4-Regel ist hier wirkungslos.

**SSH-Login mit Passwort wird abgelehnt**
→ `/etc/ssh/sshd_config.d/00-kali-app.conf` muss `PasswordAuthentication yes` enthalten. Der Name
beginnt mit `00-`, weil sshd bei doppelten Angaben den **ersten** Wert nimmt und ein späteres
`PasswordAuthentication no` des Basis-Images sonst gewinnen würde.

## Idempotenz testen

```bash
tofu plan   # sollte "No changes" zeigen
```

Zeigt es Änderungen → Fehler in HCL oder State.

## Post-Deployment-Checks

```bash
export SSH_PASS="<passwort>"
./validate.sh <user> <ipv6>
```

Zeigt zuerst den Stand der Einrichtung, danach pro Dienst, Werkzeug und Kursdatei einen eigenen
Fehler. Braucht `sshpass`.
