#!/usr/bin/env bash
set -euo pipefail

# Post-Build-Verifikation
#
# Geprueft wird, wo moeglich, Funktion statt blosser Existenz: eine Datei kann
# da sein und trotzdem Unsinn enthalten (ein unterminiertes Here-Document
# schreibt den restlichen Skriptquelltext hinein, ohne dass set -e oder der
# trap anschlagen).

trap 'echo "❌ FEHLER in $0 Zeile $LINENO"; exit 1' ERR

fehler=0

pruefe() {
  local name="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "  ✓ $name"
  else
    echo "  ❌ $name"
    fehler=$((fehler + 1))
  fi
}

echo "=== Verifikation ==="

echo "System:"
# Basis ist ein Debian-Image (siehe 01-base.sh). Ein halb umgestelltes System
# haette alle Werkzeuge und saehe trotzdem gruen aus.
pruefe "System ist Kali (ID=kali)" grep -qx 'ID=kali' /etc/os-release
pruefe "nur Kali-Paketquellen" test ! -e /etc/apt/sources.list.d/debian.sources

echo "Programme:"
pruefe "xrdp" command -v xrdp
pruefe "xfce4-session" command -v xfce4-session
for tool in nmap wireshark john burpsuite msfconsole sqlmap; do
  pruefe "$tool" command -v "$tool"
done

echo "XRDP-Konfiguration:"
# Der wichtigste Punkt des ganzen Images: IPv4 ist im DHBWV6-Netz nicht
# erreichbar, ein auf IPv4 lauschender XRDP waere unbenutzbar.
pruefe "xrdp.ini bindet auf tcp6" grep -qxF 'port=tcp6://:3389' /etc/xrdp/xrdp.ini
pruefe "xrdp.ini enable_ipv6" grep -qxF 'enable_ipv6=true' /etc/xrdp/xrdp.ini
pruefe "sesman.ini MaxSessions" grep -qxF 'MaxSessions=50' /etc/xrdp/sesman.ini
pruefe "startwm.sh ausfuehrbar" test -x /etc/xrdp/startwm.sh
pruefe "xrdp beim Boot aktiv" systemctl is-enabled xrdp

echo "Kursverzeichnis:"
pruefe "kali-kurs vorhanden" test -d /etc/skel/kali-kurs
pruefe "LIES_MICH.txt vorhanden" test -f /etc/skel/kali-kurs/LIES_MICH.txt
pruefe "LIES_MICH.txt hat Inhalt" grep -q 'KURZANLEITUNG' /etc/skel/kali-kurs/LIES_MICH.txt
# Gegenprobe: enthaelt die Datei Skriptquelltext, ist ein Here-Document
# ausgelaufen.
if grep -qE '^(chmod|find|for|cat|UEBUNGEN)' /etc/skel/kali-kurs/LIES_MICH.txt; then
  echo "  ❌ LIES_MICH.txt enthaelt Skriptquelltext (Here-Document ausgelaufen)"
  fehler=$((fehler + 1))
else
  echo "  ✓ LIES_MICH.txt ohne Skriptreste"
fi

# Fehlt das Verzeichnis, liefert find einen Fehler - mit pipefail wuerde die
# Zuweisung scheitern und der ERR-trap statt der klaren Meldung greifen.
anzahl_aufgaben="$(find /etc/skel/kali-kurs/uebungen -name aufgaben.txt -type f 2>/dev/null | wc -l)" || anzahl_aufgaben=0
if [ "$anzahl_aufgaben" -eq 5 ]; then
  echo "  ✓ 5 Uebungsverzeichnisse mit aufgaben.txt"
else
  echo "  ❌ aufgaben.txt: $anzahl_aufgaben von 5 gefunden"
  fehler=$((fehler + 1))
fi

echo "Desktop-Starter:"
anzahl_starter="$(find /etc/skel/Desktop -name '*.desktop' -type f 2>/dev/null | wc -l)" || anzahl_starter=0
if [ "$anzahl_starter" -ge 6 ]; then
  echo "  ✓ $anzahl_starter Starter"
else
  echo "  ❌ nur $anzahl_starter Starter (6 erwartet)"
  fehler=$((fehler + 1))
fi
pruefe "Autostart-Willkommen" test -f /etc/skel/.config/autostart/willkommen.desktop
pruefe "Hilfsskript kali-kurs-oeffnen" test -x /usr/local/bin/kali-kurs-oeffnen

echo ""
if [ "$fehler" -ne 0 ]; then
  echo "❌ Verifikation fehlgeschlagen: $fehler Punkt(e)"
  exit 1
fi
echo "✓ Alle kritischen Komponenten vorhanden und plausibel"

# Image-Hygiene: apt-Cache raus, machine-id zuruecksetzen, damit jede aus dem
# Image erzeugte VM eine eigene bekommt.
apt-get clean
rm -rf /var/lib/apt/lists/*
# Nur fuer den unbeaufsichtigten Build gedacht (01-base.sh); auf der Studi-VM
# soll apt bei Konfigurationsdateien wieder normal nachfragen.
rm -f /etc/apt/apt.conf.d/90-packer-noninteractive
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id || true

# Build-Benutzer aus template.pkr.hcl unbrauchbar machen. Loeschen geht hier
# nicht, weil Packer noch als "packer" angemeldet ist. Die cloud-init-Vorlage in
# terraform/ loescht ihn beim ersten Boot der Studi-VM.
if id packer >/dev/null 2>&1; then
  passwd -l packer
  usermod --expiredate 1 --shell /usr/sbin/nologin packer
fi
rm -f /etc/sudoers.d/90-cloud-init-users

# Packers temporaerer Schluessel steckt beim Standardbenutzer, bei root und bei
# "packer" (siehe user_data in template.pkr.hcl). Die Studi-VMs bekommen ihre
# Zugaenge frisch per cloud-init, hier darf keiner zurueckbleiben. Die laufende
# SSH-Sitzung bleibt davon unberuehrt.
find /root /home -path '*/.ssh/authorized_keys' -type f -delete

# cloud-init-Zustand des Builds (inkl. Build-user-data) entfernen. Jede
# Studi-VM fuehrt cloud-init ohnehin frisch aus.
cloud-init clean --logs || true

echo "=== Provisioning erfolgreich ($(date)) ==="
