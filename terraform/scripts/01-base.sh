#!/usr/bin/env bash
set -euo pipefail

# Basis-System: Debian-Cloud-Image auf Kali (kali-rolling) umstellen,
# danach debconf und essenzielle Pakete.
#
# Warum der Umweg ueber Debian: in OpenStack liegt kein Kali-Image, und Images
# koennen nur die Cloud-Admins hinzufuegen. Laeuft beim ersten Start der VM
# (cloud-init runcmd -> setup.sh), nicht mehr in einem Image-Build.

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

trap 'echo "❌ FEHLER in $0 Zeile $LINENO"; exit 1' ERR

KALI_KEYRING="/usr/share/keyrings/kali-archive-keyring.gpg"
KALI_KEYRING_URL="https://archive.kali.org/archive-keyring.gpg"
# Signierschluessel seit April 2025 (https://www.kali.org/blog/new-kali-archive-signing-key/)
KALI_FINGERPRINT="827C8569F2518CC677FECA1AED65462EC8D5E4C5"

# Desktop, Werkzeuge und Metasploit brauchen deutlich mehr als die 3 GB des
# Debian-Images. Lieber hier mit klarer Meldung abbrechen als mitten im apt.
MIN_FREE_GB=15

# Kein "cloud-init status --wait" hier: das Skript laeuft selbst innerhalb von
# cloud-init (runcmd) und wuerde auf sich selbst warten - Deadlock. growpart
# und das packages-Modul sind zu diesem Zeitpunkt schon durch.

frei_gb="$(df --output=avail -BG / | tail -n 1 | tr -dc '0-9')"
if [ "$frei_gb" -lt "$MIN_FREE_GB" ]; then
  echo "❌ Nur ${frei_gb} GB frei auf /, mindestens ${MIN_FREE_GB} GB noetig."
  echo "   Flavor mit groesserer Root-Disk waehlen (Variable flavor in terraform/variables.tf)."
  exit 1
fi
echo "✓ ${frei_gb} GB frei auf /"

# Fuer alle folgenden apt-Laeufe, auch in 02/03: bei geaenderten
# Konfigurationsdateien nie nachfragen, sonst haengt dpkg ohne Terminal.
# Lock-Timeout: beim ersten Start koennen apt-daily-Timer das dpkg-Lock halten.
# 06-verify.sh entfernt die Datei am Ende wieder.
cat > /etc/apt/apt.conf.d/90-kali-app-noninteractive <<'EOF'
Dpkg::Options {
  "--force-confdef";
  "--force-confold";
};
DPkg::Lock::Timeout "600";
EOF

# --- Kali-Archivschluessel holen und pruefen ---------------------------------
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl gnupg

curl -fsSL "$KALI_KEYRING_URL" -o "$KALI_KEYRING"

# Fingerprint statt Dateipruefsumme: Kali kann die Keyring-Datei neu ausliefern
# (alter und neuer Schluessel stecken gemeinsam drin), der Schluessel bleibt.
GNUPGHOME="$(mktemp -d)"
export GNUPGHOME
if ! gpg --show-keys --with-colons "$KALI_KEYRING" \
     | awk -F: '$1 == "fpr" { print $10 }' \
     | grep -qx "$KALI_FINGERPRINT"; then
  echo "❌ Kali-Keyring enthaelt den erwarteten Schluessel $KALI_FINGERPRINT nicht."
  exit 1
fi
rm -rf "$GNUPGHOME"
unset GNUPGHOME
echo "✓ Kali-Archivschluessel verifiziert"

# --- Paketquellen umstellen --------------------------------------------------
# Debian- und Kali-Quellen nebeneinander zerlegen das System (Kali verlangt
# neuere Bibliotheken als Debian stable). Deshalb komplett ersetzen.
rm -f /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources

cat > /etc/apt/sources.list.d/kali.sources <<EOF
Types: deb
URIs: http://http.kali.org/kali
Suites: kali-rolling
Components: main contrib non-free non-free-firmware
Signed-By: $KALI_KEYRING
EOF

# cloud-init darf beim ersten Boot der Studi-VM keine Debian-Quellen
# zurueckschreiben.
mkdir -p /etc/cloud/cloud.cfg.d
cat > /etc/cloud/cloud.cfg.d/99-kali-apt.cfg <<'EOF'
apt:
  preserve_sources_list: true
EOF

apt-get update
apt-get -y full-upgrade
apt-get -y autoremove

if ! grep -qx 'ID=kali' /etc/os-release; then
  echo "❌ Umstellung unvollstaendig: /etc/os-release meldet nicht ID=kali"
  grep '^ID=' /etc/os-release || true
  exit 1
fi
echo "✓ System ist jetzt $(. /etc/os-release && echo "$PRETTY_NAME")"

# --- Basis -------------------------------------------------------------------
echo "debconf debconf/frontend select Noninteractive" | debconf-set-selections
echo "wireshark-common wireshark-common/install-setuid boolean true" | debconf-set-selections

apt-get install -y --no-install-recommends \
  curl ca-certificates gnupg openssl tree git iproute2
