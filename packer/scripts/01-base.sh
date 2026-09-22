#!/usr/bin/env bash
set -euo pipefail

# Basis-System: apt, debconf, essenzielle Pakete

export DEBIAN_FRONTEND=noninteractive

trap 'echo "❌ FEHLER in $0 Zeile $LINENO"; exit 1' ERR

# Abwarten, bis das cloud-init des Basis-Images durch ist. Sonst streiten sich
# dessen apt-Lauf und unserer um das dpkg-Lock.
cloud-init status --wait || true

echo "debconf debconf/frontend select Noninteractive" | debconf-set-selections
echo "wireshark-common wireshark-common/install-setuid boolean true" | debconf-set-selections

apt-get update
apt-get -y upgrade

apt-get install -y --no-install-recommends \
  curl ca-certificates gnupg openssl tree git iproute2
