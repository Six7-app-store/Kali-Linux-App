#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Deployment Validation Script
#
# Prüft nach einem Terraform-Deployment, ob die VM korrekt konfiguriert ist.
# Wird lokal aufgerufen, SSH-logged sich in die VM und führt Checks durch.
#
# Usage:
#   ./validate.sh <username> <ipv6-adresse> <password>
#   oder:
#   export SSH_PASS="<password>"
#   ./validate.sh <username> <ipv6-adresse>
#
# =============================================================================

if [ $# -lt 2 ]; then
  echo "Usage: $0 <username> <ipv6-address> [password]"
  echo ""
  echo "  username:      Benutzername aus terraform output"
  echo "  ipv6-address:  IPv6-Adresse (ohne Klammern), z.B. 2001:7c0:..."
  echo "  password:      Passwort (optional, sonst SSH_PASS env var)"
  echo ""
  echo "Beispiel:"
  echo "  export SSH_PASS='geheim'"
  echo "  ./validate.sh alice 2001:7c0:1b20::1"
  exit 1
fi

USERNAME="$1"
IPV6="$2"
PASSWORD="${3:-${SSH_PASS:-}}"

if [ -z "$PASSWORD" ]; then
  echo "❌ Fehler: Passwort erforderlich (Argument 3 oder SSH_PASS env var)"
  exit 1
fi

set +e

# =============================================================================
# Hilfsfunktionen
# =============================================================================

run_check() {
  local name="$1"
  local cmd="$2"
  echo -n "  ✓ $name... "

  local output
  output=$(sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "$USERNAME@$IPV6" "$cmd" 2>&1)

  if [ $? -eq 0 ]; then
    echo "OK"
    if [ -n "$output" ] && [ "$output" != "active" ]; then
      echo "    $output"
    fi
    return 0
  else
    echo "FEHLER"
    echo "    $output"
    return 1
  fi
}

# =============================================================================
# Verbindungstest
# =============================================================================

echo "=== Deployment Validation ==="
echo "Ziel: $USERNAME@$IPV6"
echo ""

echo -n "SSH-Verbindung... "
if sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -o ConnectTimeout=5 "$USERNAME@$IPV6" "echo OK" >/dev/null 2>&1; then
  echo "OK"
else
  echo "FEHLER"
  echo "❌ Kann sich nicht mit der VM verbinden."
  echo "   Prüfe:"
  echo "   - IPv6-Adresse korrekt?"
  echo "   - Firewall lässt SSH zu (Port 22)?"
  echo "   - Cloud-Init Setup abgeschlossen? (warte ~180s nach Terraform)"
  exit 1
fi

echo ""
echo "=== Systemprüfungen ==="

FAILED=0

# SSH
run_check "SSH läuft" "systemctl is-active ssh" || ((FAILED++))

# XRDP
run_check "XRDP läuft" "systemctl is-active xrdp" || ((FAILED++))
run_check "XRDP-SessionManager läuft" "systemctl is-active xrdp-sesman" || ((FAILED++))

# XFCE
run_check "XFCE installiert" "which xfce4-session" || ((FAILED++))

# Firewall
run_check "UFW läuft" "ufw status | head -1" || ((FAILED++))
run_check "SSH (22) freigegeben" "ufw status | grep 22" || ((FAILED++))
run_check "RDP (3389) freigegeben" "ufw status | grep 3389" || ((FAILED++))

echo ""
echo "=== Software-Check ==="

# Werkzeuge
for tool in nmap wireshark john hydra sqlmap gobuster nikto aircrack-ng dirb; do
  run_check "$tool installiert" "which $tool" || ((FAILED++))
done

# Desktop-Browser
run_check "Firefox installiert" "which firefox-esr" || ((FAILED++))

echo ""
echo "=== Kurs-Verzeichnis ==="

run_check "~/kali-kurs existiert" "[ -d ~/kali-kurs ] && echo 'OK'" || ((FAILED++))
run_check "LIES_MICH.txt vorhanden" "[ -f ~/kali-kurs/LIES_MICH.txt ] && echo 'OK'" || ((FAILED++))

for ex_dir in 01-recon 02-portscan 03-traffic-analyse 04-web-schwachstellen 05-passwoerter; do
  run_check "uebungen/$ex_dir vorhanden" "[ -d ~/kali-kurs/uebungen/$ex_dir ] && echo 'OK'" || ((FAILED++))
done

echo ""
echo "=== Desktop-Integration ==="

run_check "Desktop-Verzeichnis vorhanden" "[ -d ~/Desktop ] && echo 'OK'" || ((FAILED++))
run_check "Desktop-Starter vorhanden" "[ $(ls ~/Desktop/*.desktop 2>/dev/null | wc -l) -gt 0 ] && echo 'OK'" || ((FAILED++))

run_check ".xsession konfiguriert" "[ -f ~/.xsession ] && echo 'OK'" || ((FAILED++))

echo ""
echo "=== Logs prüfen ==="

run_check "cloud-init erfolgreich" "cloud-init status --wait && echo 'OK'" || ((FAILED++))
run_check "setup-complete.log vorhanden" "[ -f /var/log/setup-complete.log ] && echo 'OK'" || ((FAILED++))

if sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  "$USERNAME@$IPV6" "grep -q 'Setup abgeschlossen' /var/log/setup-complete.log" 2>/dev/null; then
  echo "  ✓ setup-complete.log enthält Erfolgs-Marker... OK"
else
  echo "  ⚠️ setup-complete.log Erfolgs-Marker fehlt oder Fehler vorhanden"
fi

echo ""
echo "=== Ergebnis ==="

if [ $FAILED -eq 0 ]; then
  echo "✅ Alle Checks bestanden! Das Deployment ist erfolgreich."
  echo ""
  echo "Nächste Schritte:"
  echo "  - RDP-Verbindung testen: mstsc -> [$IPV6]:3389"
  echo "  - Oder SSH-Terminal: ssh $USERNAME@$IPV6"
  exit 0
else
  echo "❌ $FAILED Check(s) fehlgeschlagen."
  echo ""
  echo "Troubleshooting:"
  echo "  - SSH in die VM und prüfe: sudo systemctl status xrdp"
  echo "  - Logs: sudo journalctl -u xrdp -n 20"
  echo "  - cloud-init Logs: cat /var/log/cloud-init-output.log"
  echo "  - Firewall: sudo ufw status"
  exit 1
fi
