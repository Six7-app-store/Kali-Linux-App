#!/usr/bin/env bash
set -euo pipefail

# Post-Deployment Verifikation
#
# WICHTIG: Alle Remote-Befehle stehen in EINFACHEN Anfuehrungszeichen. In
# doppelten wuerde $(...) auf dem lokalen Rechner expandiert, nicht auf der VM
# - der Test prueft dann die eigene Maschine und ist wertlos.

if [ $# -lt 2 ]; then
  echo "Usage: $0 <username> <ipv6-address> [password]"
  echo "  export SSH_PASS='<password>'; $0 alice 2001:7c0:..."
  exit 1
fi

USERNAME="$1"
IPV6="$2"
PASSWORD="${3:-${SSH_PASS:-}}"

[ -z "$PASSWORD" ] && { echo "❌ Passwort erforderlich"; exit 1; }

command -v sshpass >/dev/null || {
  echo "❌ sshpass fehlt (apt-get install sshpass)"
  exit 1
}

set +e

SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)

FAILED=0

run_check() {
  local name="$1"
  local cmd="$2"
  printf '  %-34s ' "$name..."

  local output
  if ! output=$(sshpass -p "$PASSWORD" ssh "${SSH_OPTS[@]}" "$USERNAME@$IPV6" "$cmd" 2>&1); then
    echo "FEHLER"
    [ -n "$output" ] && echo "    $output"
    FAILED=$((FAILED + 1))
    return 1
  fi
  echo "OK"
  return 0
}

echo "=== Deployment Validation ==="
echo "Ziel: $USERNAME@$IPV6"
echo ""

sshpass -p "$PASSWORD" ssh "${SSH_OPTS[@]}" -o ConnectTimeout=10 \
  "$USERNAME@$IPV6" 'echo OK' >/dev/null 2>&1 || {
  echo "❌ SSH-Verbindung fehlgeschlagen"
  echo "   IPv6-Adresse korrekt? Security Group offen? VM noch im ersten Start?"
  exit 1
}

# Die VM richtet sich beim ersten Start selbst ein (Debian -> Kali, Desktop,
# Werkzeuge). Solange das laeuft, waeren alle folgenden Checks rot - also
# zuerst den Stand der Einrichtung zeigen statt einer Liste von Fehlern.
echo "=== Einrichtung beim ersten Start ==="
if ! sshpass -p "$PASSWORD" ssh "${SSH_OPTS[@]}" "$USERNAME@$IPV6" 'test -f /var/lib/kali-app/ready' 2>/dev/null; then
  stand="$(sshpass -p "$PASSWORD" ssh "${SSH_OPTS[@]}" "$USERNAME@$IPV6" \
    'grep -E "^===|❌" /var/log/kali-app-setup.log 2>/dev/null | tail -3' 2>/dev/null)"
  if printf '%s' "$stand" | grep -q '❌'; then
    echo "❌ Einrichtung fehlgeschlagen. Letzte Meldungen:"
  else
    echo "⏳ Einrichtung laeuft noch. Letzter Schritt:"
  fi
  printf '%s\n' "${stand:-   (noch kein Protokoll - cloud-init startet gerade)}" | sed 's/^/   /'
  echo "   Vollstaendig: ssh $USERNAME@$IPV6 'tail -f /var/log/kali-app-setup.log'"
  exit 1
fi
echo "  ✓ Einrichtung abgeschlossen"
echo ""

echo "=== Dienste ==="
run_check "SSH" 'systemctl is-active ssh'
run_check "XRDP" 'systemctl is-active xrdp'
run_check "XRDP-SessionManager" 'systemctl is-active xrdp-sesman'

# Der eigentliche Knackpunkt: nicht "laeuft xrdp", sondern "ist er ueber IPv6
# erreichbar". Eine IPv4-Bindung waere im DHBWV6-Netz nutzlos.
run_check "XRDP lauscht auf IPv6:3389" 'ss -tln | grep 3389 | grep -q "::"'

echo ""
echo "=== Werkzeuge ==="
for tool in nmap wireshark tcpdump john burpsuite msfconsole; do
  run_check "$tool" "command -v $tool"
done

echo ""
echo "=== Kursverzeichnis ==="
# $HOME statt ~: in einfachen Anführungszeichen wird beides erst auf der VM
# ausgewertet, aber die Tilde bliebe in manchen Kontexten stehen.
run_check "kali-kurs" 'test -d $HOME/kali-kurs'
run_check "LIES_MICH.txt lesbar" 'grep -q KURZANLEITUNG $HOME/kali-kurs/LIES_MICH.txt'
run_check "5x aufgaben.txt" 'test "$(find $HOME/kali-kurs/uebungen -name aufgaben.txt -type f | wc -l)" -eq 5'
run_check "Desktop-Starter" 'ls $HOME/Desktop/*.desktop >/dev/null 2>&1'

echo ""
if [ "$FAILED" -eq 0 ]; then
  echo "✅ Deployment erfolgreich!"
  echo "   RDP: mstsc -> [$IPV6]:3389"
  echo "   SSH: ssh $USERNAME@$IPV6"
  exit 0
fi

echo "❌ $FAILED Fehler gefunden"
echo "   Siehe TROUBLESHOOTING.md"
exit 1
