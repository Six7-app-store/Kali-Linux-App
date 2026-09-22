#!/usr/bin/env bash
set -euo pipefail

# Orchestrator für Kali-Provisioning
# Ruft die einzelnen Steps in Reihenfolge auf

trap 'echo "❌ Provisioning fehlgeschlagen in Zeile $LINENO"; exit 1' ERR

SCRIPTS_DIR="$(dirname "$0")"
cd "$SCRIPTS_DIR"

echo "=== Kali-Linux Provisioning ==="

for step in 01-base.sh 02-desktop.sh 03-tools.sh 04-integration.sh 05-verify.sh; do
  echo ""
  echo "→ Führe aus: $step"
  bash "$step" || { echo "❌ $step fehlgeschlagen"; exit 1; }
done

echo ""
echo "✅ Provisioning erfolgreich abgeschlossen"
