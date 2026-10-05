#!/usr/bin/env bash
set -euo pipefail

# Kursmaterial und Rechte fuer die bereits angelegten Studi-Accounts.
#
# Aufruf: 05-users.sh <benutzer>...   (setup.sh reicht die Namen durch)
#
# Ohne Image-Build legt cloud-init die Accounts beim ersten Start an, BEVOR
# 04-integration.sh /etc/skel befuellt. useradd kopiert /etc/skel nur beim
# Anlegen - die Home-Verzeichnisse waeren also leer (kein kali-kurs, keine
# Desktop-Starter). Ausserdem gibt es die Gruppe "wireshark" erst nach
# 03-tools.sh; cloud-init kann die Accounts deshalb nicht selbst hineinlegen.

trap 'echo "❌ FEHLER in $0 Zeile $LINENO"; exit 1' ERR

if [ "$#" -eq 0 ]; then
  echo "Keine Studi-Accounts uebergeben - nichts zu tun."
  exit 0
fi

for benutzer in "$@"; do
  if ! id "$benutzer" >/dev/null 2>&1; then
    echo "❌ Account $benutzer existiert nicht (cloud-init users)."
    exit 1
  fi

  home="$(getent passwd "$benutzer" | cut -d: -f6)"
  gruppe="$(id -gn "$benutzer")"

  # -n: nichts ueberschreiben, was der Account schon hat (idempotent, falls
  # setup.sh erneut laeuft).
  cp -rn /etc/skel/. "$home/"
  chown -R "$benutzer:$gruppe" "$home"

  # Mitschnitt ohne root (wireshark-common wurde mit install-setuid
  # vorkonfiguriert, siehe 01-base.sh).
  usermod -aG wireshark "$benutzer"

  echo "✓ $benutzer: Kursmaterial kopiert, Gruppe wireshark"
done
