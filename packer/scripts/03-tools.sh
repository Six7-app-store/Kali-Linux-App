#!/usr/bin/env bash
set -euo pipefail

# Kali-Werkzeuge (kuratiert)

export DEBIAN_FRONTEND=noninteractive
trap 'echo "❌ FEHLER in $0 Zeile $LINENO"; exit 1' ERR

apt-get install -y \
  nmap wireshark burpsuite metasploit-framework john hydra sqlmap gobuster \
  netcat-traditional aircrack-ng dirb nikto wordlists
