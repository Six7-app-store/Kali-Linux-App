#!/usr/bin/env bash
set -euo pipefail

# XFCE + XRDP auf IPv6

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
trap 'echo "❌ FEHLER in $0 Zeile $LINENO"; exit 1' ERR

# INI-Schluessel setzen und das Ergebnis pruefen.
#
# "sed -i" meldet auch dann Erfolg, wenn das Muster nirgends passt. Ein
# "sed ... || fallback" waere also wirkungslos - der Fallback liefe nie, und
# eine fehlende Zeile fiele erst beim ersten RDP-Versuch auf.
#
# Nur innerhalb von [section]. Die fruehere Fassung ersetzte den Schluessel in
# der ganzen Datei: "port=" steht in xrdp.ini aber in fast jedem Abschnitt.
# [Xorg] bekam so "port=tcp6://:3389" statt "port=-1" (lokaler Sesman), und
# jede Anmeldung scheiterte mit "error - no ip set" (gesehen am 15.10.2026).
# In [Channels] wurde dabei ausserdem ein absichtlich auskommentiertes
# "#port=" aktiviert.
set_ini_key() {
  local file="$1" section="$2" key="$3" value="$4" tmp
  tmp="$(mktemp)"

  awk -v sec="[${section}]" -v key="$key" -v val="$value" '
    # Fehlt der Schluessel im Abschnitt, ans Ende des Abschnitts haengen.
    function anhaengen() { if (drin && !gesetzt) { print key "=" val; gesetzt = 1 } }
    /^\[/ { anhaengen(); drin = ($0 == sec) }
    drin && index($0, key "=") == 1 || drin && index($0, "#" key "=") == 1 {
      if (!gesetzt) { print key "=" val; gesetzt = 1 }
      next
    }
    { print }
    END { anhaengen() }
  ' "$file" > "$tmp"
  cat "$tmp" > "$file"
  rm -f "$tmp"

  awk -v sec="[${section}]" -v zeile="${key}=${value}" '
    /^\[/ { drin = ($0 == sec) }
    drin && $0 == zeile { gefunden = 1 }
    END { exit !gefunden }
  ' "$file" || {
    echo "❌ $file: ${key}=${value} in [${section}] konnte nicht gesetzt werden"
    exit 1
  }
}

apt-get install -y kali-linux-headless kali-desktop-xfce

apt-get install -y xrdp xorgxrdp dbus-x11 firefox-esr xfce4-terminal thunar mousepad xdg-user-dirs

# IPv6-Binding (kritisch — IPv4 ist im DHBWV6-Netz nicht erreichbar)
set_ini_key /etc/xrdp/xrdp.ini Globals port "tcp6://:3389"
set_ini_key /etc/xrdp/xrdp.ini Globals enable_ipv6 true

printf 'net.ipv6.bindv6only = 0\n' > /etc/sysctl.d/60-xrdp-dualstack.conf

# XRDP-Sitzungsgrenzen (mehrere Studierende gleichzeitig auf einer VM)
set_ini_key /etc/xrdp/sesman.ini Sessions MaxSessions 50
set_ini_key /etc/xrdp/sesman.ini Sessions KillDisconnected false
set_ini_key /etc/xrdp/sesman.ini Sessions DisconnectedTimeLimit 3600
set_ini_key /etc/xrdp/sesman.ini Sessions IdleTimeLimit 0

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
printf 'PasswordAuthentication yes\n' > /etc/ssh/sshd_config.d/60-password-auth.conf
