#!/usr/bin/env bash
set -euo pipefail

# XFCE + XRDP auf IPv6

export DEBIAN_FRONTEND=noninteractive
trap 'echo "❌ FEHLER in $0 Zeile $LINENO"; exit 1' ERR

apt-get install -y kali-linux-headless kali-desktop-xfce

apt-get install -y xrdp xorgxrdp dbus-x11 firefox-esr xfce4-terminal thunar mousepad xdg-user-dirs

# IPv6-Binding (kritisch — IPv4 ist im DHBWV6-Netz nicht erreichbar)
sed -i 's|^port=.*|port=tcp6://:3389|' /etc/xrdp/xrdp.ini
sed -i 's|^#\?enable_ipv6=.*|enable_ipv6=true|' /etc/xrdp/xrdp.ini || \
  sed -i '/^\[Globals\]/a enable_ipv6=true' /etc/xrdp/xrdp.ini

printf 'net.ipv6.bindv6only = 0\n' | tee /etc/sysctl.d/60-xrdp-dualstack.conf > /dev/null

# XRDP-Sitzungsgrenzen
sed -i \
  -e 's|^MaxSessions=.*|MaxSessions=50|' \
  -e 's|^KillDisconnected=.*|KillDisconnected=false|' \
  -e 's|^DisconnectedTimeLimit=.*|DisconnectedTimeLimit=3600|' \
  -e 's|^IdleTimeLimit=.*|IdleTimeLimit=0|' \
  /etc/xrdp/sesman.ini

cat > /etc/xrdp/startwm.sh <<'EOF'
#!/bin/sh
[ -r /etc/default/locale ] && . /etc/default/locale && export LANG LANGUAGE
exec /usr/bin/startxfce4
EOF
chmod 755 /etc/xrdp/startwm.sh

adduser xrdp ssl-cert || true

# Polkit (keine Passwort-Dialoge in RDP-Sessions)
mkdir -p /etc/polkit-1/rules.d
cat > /etc/polkit-1/rules.d/49-kali-desktop.rules <<'EOF'
polkit.addRule(function (action, subject) {
    if (action.id.indexOf("org.freedesktop.color-manager.") === 0) {
        return polkit.Result.YES;
    }
});
polkit.addRule(function (action, subject) {
    if ((action.id.indexOf("org.freedesktop.NetworkManager.") === 0 ||
         action.id === "org.freedesktop.packagekit.system-sources-refresh") &&
        subject.isInGroup("sudo")) {
        return polkit.Result.YES;
    }
});
EOF

mkdir -p /etc/polkit-1/localauthority/50-local.d
cat > /etc/polkit-1/localauthority/50-local.d/49-kali-desktop.pkla <<'EOF'
[Farbprofile ohne Nachfrage]
Identity=unix-group:sudo
Action=org.freedesktop.color-manager.*
ResultAny=no
ResultInactive=no
ResultActive=yes
EOF

systemctl enable xrdp xrdp-sesman

# SSH Passwort-Auth vorbereiten
mkdir -p /etc/ssh/sshd_config.d
printf 'PasswordAuthentication yes\n' | tee /etc/ssh/sshd_config.d/60-password-auth.conf > /dev/null
