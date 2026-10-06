#!/usr/bin/env bash
set -euo pipefail

# Einrichtung beim ersten Start der VM (aus cloud-init runcmd).
#
# Aufruf: setup.sh <benutzer>...
#
# Fuehrt alle nummerierten Skripte (NN-*.sh) in diesem Verzeichnis in
# Namensreihenfolge aus und reicht die Studi-Accounts an jedes durch. Ein neuer
# Schritt braucht deshalb nur eine neue Datei - keine Liste, die man vergessen
# kann nachzutragen (siehe main.tf: es wird das ganze Verzeichnis ausgeliefert).
#
# Status fuer Menschen:
#   /var/log/kali-app-setup.log   vollstaendiges Protokoll (lesbar fuer alle)
#   /etc/motd                     Hinweis beim SSH-Login: laeuft / fertig / Fehler
#   /var/lib/kali-app/ready       existiert genau dann, wenn alles durchlief

SKRIPTE="$(cd "$(dirname "$0")" && pwd)"
LOG=/var/log/kali-app-setup.log
READY=/var/lib/kali-app/ready

install -m 644 /dev/null "$LOG"
mkdir -p "$(dirname "$READY")"
rm -f "$READY"
exec > >(tee -a "$LOG") 2>&1

fehlgeschlagen() {
  local rc=$?
  cat > /etc/motd <<EOF

  ❌ Die Einrichtung dieser Kali-VM ist fehlgeschlagen (Exit $rc).
     Protokoll: $LOG
     Bitte an die Kursbetreuung melden.

EOF
  echo "❌ Einrichtung fehlgeschlagen ($(date))"
  exit "$rc"
}
trap fehlgeschlagen ERR

echo "=== Kali-App: Einrichtung startet ($(date)) ==="

for skript in "$SKRIPTE"/[0-9][0-9]-*.sh; do
  echo ""
  echo "=== $(basename "$skript") ==="
  bash "$skript" "$@"
done

echo ""
echo "=== Dienste ==="
systemctl enable --now xrdp xrdp-sesman
systemctl restart xrdp ssh

[ "$(systemctl is-active ssh)" = "active" ] || { echo "❌ SSH nicht aktiv"; false; }
[ "$(systemctl is-active xrdp)" = "active" ] || { echo "❌ XRDP nicht aktiv"; false; }
# Nicht nur "laeuft der Dienst", sondern "lauscht er auf IPv6". Ein auf IPv4
# gebundener XRDP waere im DHBWV6-Netz nicht erreichbar.
ss -tln | grep -q '\[::\]:3389' || { echo "❌ XRDP lauscht nicht auf IPv6:3389"; false; }
echo "✓ SSH und XRDP aktiv, XRDP auf [::]:3389"

cat > /etc/motd <<'EOF'

  ✅ Kali-Desktop bereit. Remotedesktop: [<IPv6-Adresse>]:3389

EOF
touch "$READY"
echo ""
echo "=== Kali-App: Einrichtung erfolgreich ($(date)) ==="
