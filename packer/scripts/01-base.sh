#!/usr/bin/env bash
set -euo pipefail

# Basis-System: apt, debconf, essenzielle Pakete

export DEBIAN_FRONTEND=noninteractive

trap 'echo "❌ FEHLER in $0 Zeile $LINENO"; exit 1' ERR

cloud-init status --wait || true

echo "debconf debconf/frontend select Noninteractive" | debconf-set-selections
echo "wireshark-common wireshark-common/install-setuid boolean true" | debconf-set-selections

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get -y upgrade

apt-get install -y --no-install-recommends \
  curl ca-certificates gnupg openssl tree git
