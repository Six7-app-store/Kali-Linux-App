#!/usr/bin/env bash
set -euo pipefail

# Zweite Schnittstelle fuer ip_mode dual einrichten.
#
# Bei dual haengt die VM mit der Hauptschnittstelle im IPv6-Netz und bekommt
# nach dem Boot eine zweite im IPv4-Netz (interface_attach in main.tofu).
# Antworten von deren Adresse muessen ueber deren eigenes Gateway hinaus,
# sonst verwirft Neutrons Port-Security sie als gefaelschten Absender. Das
# braucht eine eigene Routing-Tabelle und eine Regel "from <adresse>".
#
# Die Linux-Apps erledigen das mit netplan. Hier nicht: nach der Umstellung
# auf Kali verwaltet NetworkManager das Netz, vorher ifupdown aus Debian
# (siehe 07-ipv6.sh). Deshalb setzt ein eigener Dienst Adresse, Routen und
# Regel bei jedem Boot direkt mit ip, und NetworkManager laesst die Karte in
# Ruhe. Die Werte schreibt cloud-init nach /etc/kali-app/secondary-ipv4.

export DEBIAN_FRONTEND=noninteractive
trap 'echo "❌ FEHLER in $0 Zeile $LINENO"; exit 1' ERR

KONFIG=/etc/kali-app/secondary-ipv4

if [ ! -s "$KONFIG" ]; then
  echo "✓ keine zweite Schnittstelle (ip_mode ist nicht dual)"
  exit 0
fi

read -r mac _ _ _ <"$KONFIG"

# NetworkManager soll die Karte nicht per DHCP mit eigener Default-Route
# einrichten - die Routen setzt der Dienst unten.
mkdir -p /etc/NetworkManager/conf.d
cat > /etc/NetworkManager/conf.d/90-kali-app-ipv4.conf <<EOF
[keyfile]
unmanaged-devices=mac:${mac}
EOF

install -m 755 /dev/stdin /usr/local/sbin/kali-app-ipv4 <<'SKRIPT'
#!/usr/bin/env bash
# Richtet die zweite Schnittstelle (ip_mode dual) mit eigener Routing-Tabelle
# ein (08-ipv4.sh der Kali-App). Ausgabe geht in die serielle Konsole.
set -uo pipefail

read -r mac adresse netz gateway </etc/kali-app/secondary-ipv4

# Die Karte kommt erst nach dem Boot dazu; bis zu fuenf Minuten warten.
geraet=""
for _ in $(seq 1 60); do
  for pfad in /sys/class/net/*; do
    if [ "$(cat "$pfad/address" 2>/dev/null)" = "$mac" ]; then
      geraet="$(basename "$pfad")"
    fi
  done
  [ -n "$geraet" ] && break
  sleep 5
done
if [ -z "$geraet" ]; then
  echo "kali-app-ipv4: kein Interface mit MAC $mac - die VM bleibt ueber IPv6 erreichbar"
  exit 1
fi

ip link set dev "$geraet" up
ip addr replace "$adresse" dev "$geraet"
ip route replace "$netz" dev "$geraet" table 100
ip route replace default via "$gateway" dev "$geraet" table 100
# Regel nur einmal: bei einem zweiten Lauf erst die alte entfernen
ip rule del from "${adresse%/*}" table 100 2>/dev/null || true
ip rule add from "${adresse%/*}" table 100 priority 100

echo "kali-app-ipv4: $adresse auf $geraet, Antworten ueber $gateway (Tabelle 100)"
SKRIPT

cat > /etc/systemd/system/kali-app-ipv4.service <<'UNIT'
[Unit]
Description=Kali-App: zweite Schnittstelle (IPv4) mit eigener Routing-Tabelle
Wants=network-online.target
After=network-online.target NetworkManager.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/kali-app-ipv4
# In die serielle Konsole, damit es ueber die OpenStack-API lesbar ist.
StandardOutput=journal+console
StandardError=journal+console

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable kali-app-ipv4.service
echo "✓ kali-app-ipv4.service eingerichtet (laeuft ab dem naechsten Boot)"
