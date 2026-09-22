#!/usr/bin/env bash
set -euo pipefail

# Post-Build-Verifikation

trap 'echo "❌ FEHLER in $0 Zeile $LINENO"; exit 1' ERR

echo "=== Verifikation ==="

which xrdp >/dev/null || { echo "❌ XRDP nicht gefunden"; exit 1; }
which xfce4-session >/dev/null || { echo "❌ XFCE nicht gefunden"; exit 1; }
[ -d /etc/skel/kali-kurs ] || { echo "❌ kali-kurs-Verzeichnis fehlt"; exit 1; }
[ -f /etc/skel/kali-kurs/LIES_MICH.txt ] || { echo "❌ LIES_MICH.txt fehlt"; exit 1; }
[ -d /etc/skel/Desktop ] && [ $(ls /etc/skel/Desktop/*.desktop 2>/dev/null | wc -l) -gt 0 ] || \
  { echo "❌ Desktop-Starter fehlen"; exit 1; }

echo "✓ Alle kritischen Komponenten vorhanden"

apt-get clean
rm -rf /var/lib/apt/lists/*
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id || true

echo "=== Provisioning erfolgreich ($(date)) ==="
