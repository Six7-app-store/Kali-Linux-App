#!/usr/bin/env bash
set -euo pipefail

# Einrichtung beim ersten Start der VM (aus cloud-init runcmd).
#
# Aufruf: setup.sh <benutzer>...
#
# Fuehrt alle nummerierten Skripte (NN-*.sh) in diesem Verzeichnis in
# Namensreihenfolge aus und reicht die Studi-Accounts an jedes durch. Ein neuer
# Schritt braucht deshalb nur eine neue Datei - keine Liste, die man vergessen
# kann nachzutragen (siehe main.tofu: es wird das ganze Verzeichnis ausgeliefert).
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
# gebundener XRDP (0.0.0.0:3389) waere im DHBWV6-Netz nicht erreichbar.
#
# ss zeigt einen IPv6-Socket je nach bindv6only verschieden: reines IPv6 als
# "[::]:3389", Dual-Stack als "*:3389". 02-desktop.sh setzt bindv6only=0, also
# Dual-Stack - die fruehere Pruefung nur auf "[::]:3389" schlug deshalb immer
# fehl, obwohl XRDP lauschte (gesehen am 14.10.2026). Nach dem Neustart oben
# braucht XRDP ausserdem einen Moment, bis der Socket steht.
xrdp_ipv6=false
for _ in $(seq 1 30); do
  if ss -tlnH 'sport = :3389' | awk '{print $4}' | grep -qE '^(\[::\]|\*):3389$'; then
    xrdp_ipv6=true
    break
  fi
  sleep 1
done
if [ "$xrdp_ipv6" != true ]; then
  echo "❌ XRDP lauscht nicht auf IPv6:3389"
  ss -tln | grep ':3389' || echo "   (gar kein Socket auf 3389)"
  false
fi
echo "✓ SSH und XRDP aktiv, XRDP auf IPv6:3389"

cat > /etc/motd <<'EOF'

  ✅ Kali-Desktop bereit. Remotedesktop: [<IPv6-Adresse>]:3389

EOF
touch "$READY"
echo ""
echo "=== Kali-App: Einrichtung erfolgreich ($(date)) ==="
