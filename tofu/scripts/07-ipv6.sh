#!/usr/bin/env bash
set -euo pipefail

# IPv6-Adresse nach dem Neustart in Kali sicherstellen.
#
# Gesehen am 14.10.2026 (v2.0.3): Die Einrichtung lief durch, die VM startete
# neu - und war danach weder per SSH noch per RDP erreichbar. Nach dem Boot
# hatte eth0 nur noch die private IPv4 (10.200.x.x) und eine Link-lokale
# IPv6-Adresse, die von OpenStack vergebene globale fehlte. Im DHBWV6-Netz
# ist aber nur IPv6 von aussen erreichbar.
#
# Vor dem Neustart richtete Debian das Netz ein, danach uebernimmt der mit
# Kali installierte NetworkManager eth0 und bezieht die IPv6 nicht per
# DHCPv6 (das Subnetz ist dhcpv6-stateful). Warum genau, war von aussen
# nicht zu sehen.
#
# Darum zwei Dinge bei jedem Boot:
#   1. Den Netzwerkzustand in die serielle Konsole schreiben. Die ist ueber
#      die OpenStack-API lesbar ("openstack console log show"), auch wenn die
#      VM ueber das Netz nicht erreichbar ist.
#   2. Fehlt nach 60 s noch immer eine globale IPv6, die Adresse aus den
#      OpenStack-Metadaten holen (ueber IPv4, das funktioniert) und fest in
#      NetworkManager eintragen. Andere Adressen als die vergebene laesst
#      OpenStack ohnehin nicht durch - die feste Adresse ist also genau
#      die, die per DHCPv6 gekommen waere.

export DEBIAN_FRONTEND=noninteractive
trap 'echo "❌ FEHLER in $0 Zeile $LINENO"; exit 1' ERR

install -m 755 /dev/stdin /usr/local/sbin/kali-app-ipv6 <<'SKRIPT'
#!/usr/bin/env bash
# Stellt die von OpenStack vergebene IPv6-Adresse sicher (07-ipv6.sh der
# Kali-App). Ausgabe geht in die serielle Konsole.
set -uo pipefail

METADATA=http://169.254.169.254/openstack/latest/network_data.json

global_v6() {
  ip -6 -o addr show scope global 2>/dev/null | awk '{print $2, $4}'
}

zustand() {
  echo "kali-app-ipv6: $1"
  ip -6 -o addr show 2>/dev/null | awk '{print "kali-app-ipv6:   " $2, $4, $NF}'
  nmcli -t -f DEVICE,STATE,CONNECTION device 2>/dev/null | sed 's/^/kali-app-ipv6:   nmcli /'
}

for _ in $(seq 1 60); do
  if [ -n "$(global_v6)" ]; then
    zustand "globale IPv6 vorhanden"
    exit 0
  fi
  sleep 1
done

zustand "nach 60 s keine globale IPv6 - hole sie aus den Metadaten"

if ! daten="$(curl -fsS --max-time 10 "$METADATA")"; then
  echo "kali-app-ipv6: Metadaten nicht abrufbar ($METADATA)"
  exit 1
fi

# Liefert: <Interface> <Adresse>/<Praefix> <Gateway oder ->
ziel="$(printf '%s' "$daten" | python3 -c '
import ipaddress, json, sys
daten = json.load(sys.stdin)
macs = {l["id"]: l.get("ethernet_mac_address", "").lower() for l in daten.get("links", [])}
for netz in daten.get("networks", []):
    if not netz.get("type", "").startswith("ipv6") or not netz.get("ip_address"):
        continue
    maske = str(netz.get("netmask") or "64")
    # OpenStack liefert die Maske als Adresse (ffff:ffff:ffff:ffff::), nicht als Praefix.
    praefix = int(maske) if maske.isdigit() else bin(int(ipaddress.IPv6Address(maske))).count("1")
    gw = next((r.get("gateway") for r in netz.get("routes", []) if r.get("network") == "::"), None)
    print(macs.get(netz.get("link"), ""), netz["ip_address"] + "/" + str(praefix), gw or "-")
    break
')"

if [ -z "$ziel" ]; then
  echo "kali-app-ipv6: keine IPv6-Adresse in den Metadaten"
  exit 1
fi
read -r mac adresse gateway <<<"$ziel"

geraet=""
for pfad in /sys/class/net/*; do
  if [ "$(cat "$pfad/address" 2>/dev/null)" = "$mac" ]; then
    geraet="$(basename "$pfad")"
  fi
done
if [ -z "$geraet" ]; then
  echo "kali-app-ipv6: kein Interface mit MAC $mac"
  exit 1
fi

verbindung="$(nmcli -g GENERAL.CONNECTION device show "$geraet" 2>/dev/null)"
if [ -z "$verbindung" ]; then
  echo "kali-app-ipv6: $geraet hat keine NetworkManager-Verbindung"
  exit 1
fi

echo "kali-app-ipv6: trage $adresse (Gateway $gateway) fest in \"$verbindung\" auf $geraet ein"
argumente=(ipv6.method manual ipv6.addresses "$adresse")
if [ "$gateway" != "-" ]; then
  argumente+=(ipv6.gateway "$gateway")
fi
nmcli connection modify "$verbindung" "${argumente[@]}"
nmcli connection up "$verbindung" >/dev/null

for _ in $(seq 1 15); do
  if [ -n "$(global_v6)" ]; then
    zustand "globale IPv6 jetzt vorhanden"
    exit 0
  fi
  sleep 1
done
zustand "IPv6 auch nach dem Eintragen nicht vorhanden"
exit 1
SKRIPT

cat > /etc/systemd/system/kali-app-ipv6.service <<'UNIT'
[Unit]
Description=Kali-App: von OpenStack vergebene IPv6-Adresse sicherstellen
Wants=network-online.target
After=network-online.target NetworkManager.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/kali-app-ipv6
# In die serielle Konsole, damit es ueber die OpenStack-API lesbar ist.
StandardOutput=journal+console
StandardError=journal+console

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable kali-app-ipv6.service
echo "✓ kali-app-ipv6.service eingerichtet (laeuft ab dem naechsten Boot)"
