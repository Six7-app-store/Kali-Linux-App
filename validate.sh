#!/usr/bin/env bash
set -euo pipefail

# Post-Deployment Verifikation

if [ $# -lt 2 ]; then
  echo "Usage: $0 <username> <ipv6-address> [password]"
  echo "  export SSH_PASS='<password>'; $0 alice 2001:7c0:..."
  exit 1
fi

USERNAME="$1"
IPV6="$2"
PASSWORD="${3:-${SSH_PASS:-}}"

[ -z "$PASSWORD" ] && { echo "❌ Passwort erforderlich"; exit 1; }

set +e

run_check() {
  local name="$1"
  local cmd="$2"
  echo -n "  ✓ $name... "

  local output
  output=$(sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "$USERNAME@$IPV6" "$cmd" 2>&1) || {
    echo "FEHLER"
    echo "    $output"
    return 1
  }
  echo "OK"
  return 0
}

echo "=== Deployment Validation ==="
echo "Ziel: $USERNAME@$IPV6"
echo ""

sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -o ConnectTimeout=5 "$USERNAME@$IPV6" "echo OK" >/dev/null 2>&1 || {
  echo "❌ SSH-Verbindung fehlgeschlagen"
  echo "   IPv6-Adresse korrekt? Firewall offen? cloud-init noch läuft?"
  exit 1
}

FAILED=0

echo "=== Systemprüfungen ==="
run_check "SSH" "systemctl is-active ssh" || ((FAILED++))
run_check "XRDP" "systemctl is-active xrdp" || ((FAILED++))
run_check "XRDP-SessionManager" "systemctl is-active xrdp-sesman" || ((FAILED++))
run_check "UFW" "ufw status | head -1" || ((FAILED++))
run_check "Port 22 offen" "ufw status | grep 22" || ((FAILED++))
run_check "Port 3389 offen" "ufw status | grep 3389" || ((FAILED++))

echo ""
echo "=== Werkzeuge ==="
for tool in nmap wireshark john burpsuite; do
  run_check "$tool" "which $tool" || ((FAILED++))
done

echo ""
echo "=== Kursverzeichnis ==="
run_check "~/kali-kurs" "[ -d ~/kali-kurs ] && echo OK" || ((FAILED++))
run_check "Desktop-Starter" "[ $(ls ~/Desktop/*.desktop 2>/dev/null | wc -l) -gt 0 ] && echo OK" || ((FAILED++))

echo ""
if [ $FAILED -eq 0 ]; then
  echo "✅ Deployment erfolgreich!"
  echo "   RDP: mstsc -> [$IPV6]:3389"
  echo "   SSH: ssh $USERNAME@$IPV6"
  exit 0
else
  echo "❌ $FAILED Fehler gefunden"
  echo "   Siehe TROUBLESHOOTING.md"
  exit 1
fi
