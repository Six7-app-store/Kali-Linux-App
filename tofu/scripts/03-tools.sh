#!/usr/bin/env bash
set -euo pipefail

# Kali-Werkzeuge (kuratiert)

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
trap 'echo "❌ FEHLER in $0 Zeile $LINENO"; exit 1' ERR

# tcpdump ist bewusst dabei: die Kurzanleitung nennt es, und ohne das Paket
# liefe die Uebung "Netzwerkverkehr analysieren" ins Leere.
apt-get install -y \
  nmap wireshark tcpdump burpsuite metasploit-framework john hydra sqlmap gobuster \
  netcat-traditional aircrack-ng dirb nikto wordlists
