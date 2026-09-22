#!/usr/bin/env bash
set -euo pipefail

# Desktop-Integration + Kursverzeichnis unter /etc/skel

trap 'echo "❌ FEHLER in $0 Zeile $LINENO"; exit 1' ERR

SKEL="/etc/skel"

# Hilfsskripte
mkdir -p /usr/local/bin
cat > /usr/local/bin/kali-kurs-oeffnen <<'EOF'
#!/bin/sh
exec thunar "$HOME/kali-kurs"
EOF

cat > /usr/local/bin/kali-kurs-lies-mich <<'EOF'
#!/bin/sh
exec mousepad "$HOME/kali-kurs/LIES_MICH.txt"
EOF

cat > /usr/local/bin/kali-willkommen <<'EOF'
#!/bin/sh
STAMP="$HOME/.config/kali-willkommen-gesehen"
[ -e "$STAMP" ] && exit 0
mkdir -p "$(dirname "$STAMP")"
touch "$STAMP"
exec mousepad "$HOME/kali-kurs/LIES_MICH.txt"
EOF

chmod 755 /usr/local/bin/kali-{kurs-oeffnen,kurs-lies-mich,willkommen}

# Desktop-Verzeichnis
mkdir -p "$SKEL/Desktop" "$SKEL/.config/autostart" "$SKEL/.config/xfce4/terminal"

cat > "$SKEL/.config/user-dirs.dirs" <<'EOF'
XDG_DESKTOP_DIR="$HOME/Desktop"
XDG_DOWNLOAD_DIR="$HOME/Downloads"
XDG_DOCUMENTS_DIR="$HOME/Documents"
EOF

printf 'enabled=False\n' | tee /etc/xdg/user-dirs.conf > /dev/null

printf '#!/bin/sh\nexec /usr/bin/startxfce4\n' | tee "$SKEL/.xsession" > /dev/null
chmod 755 "$SKEL/.xsession"

# Desktop-Starter
for name in "kurs-uebungen:Kurs-Übungen:Übungsaufgaben:folder-documents:kali-kurs-oeffnen" \
            "kurs-anleitung:Kurzanleitung:Befehlsreferenz:text-x-generic:kali-kurs-lies-mich" \
            "terminal:Terminal:Kali-Terminal öffnen:utilities-terminal:xfce4-terminal" \
            "firefox:Firefox:Webbrowser:firefox-esr:firefox-esr %u" \
            "wireshark:Wireshark:Netzwerkverkehr analysieren:wireshark:wireshark" \
            "burpsuite:Burp Suite:Web-Proxy:burpsuite:burpsuite"; do
  IFS=':' read id title comment icon cmd <<< "$name"
  cat > "$SKEL/Desktop/$id.desktop" <<DESKTOP
[Desktop Entry]
Version=1.0
Type=Application
Name=$title
Comment=$comment
Exec=$cmd
Icon=$icon
Terminal=false
Categories=Education;
DESKTOP
done

chmod 755 "$SKEL"/Desktop/*.desktop

cat > "$SKEL/.config/autostart/willkommen.desktop" <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Willkommen
Comment=Kurzanleitung beim ersten Login
Exec=kali-willkommen
Icon=text-x-generic
Terminal=false
X-GNOME-Autostart-enabled=true
EOF

cat > "$SKEL/.config/mimeapps.list" <<'EOF'
[Default Applications]
text/plain=org.xfce.mousepad.desktop;mousepad.desktop;
text/csv=org.xfce.mousepad.desktop;mousepad.desktop;
text/html=firefox-esr.desktop;
application/vnd.tcpdump.pcap=wireshark.desktop;
application/x-pcapng=wireshark.desktop;
inode/directory=thunar.desktop;
EOF

cat > "$SKEL/.config/xfce4/terminal/terminalrc" <<'EOF'
[Configuration]
FontName=Monospace 11
ScrollingLines=10000
MiscAlwaysShowTabs=FALSE
MiscConfirmClose=FALSE
EOF

# Kursverzeichnis
KURS_DIR="$SKEL/kali-kurs"
mkdir -p "$KURS_DIR/uebungen"/{01-recon,02-portscan,03-traffic-analyse,04-web-schwachstellen,05-passwoerter}

cat > "$KURS_DIR/LIES_MICH.txt" <<'KURS'
╔══════════════════════════════════════════════════════════════════════════════╗
║                    KALI LINUX – KURZANLEITUNG                              ║
╚══════════════════════════════════════════════════════════════════════════════╝

Willkommen auf deiner Kali-VM!

SPIELREGELN:
  Diese Werkzeuge dürfen NUR auf freigegebenen Zielen eingesetzt werden.
  Scans ohne Erlaubnis sind strafbar (§ 202a-c StGB).

DESKTOP & SITZUNG:
  - Abmelden: Anwendungen → Abmelden
  - Terminal: Strg+Alt+T oder Desktop-Starter
  - Dateimanager: Thunar (Desktop-Starter)

WERKZEUGE (eingebaute Hilfe):
  nmap, wireshark, tcpdump, netcat           — Netzwerk
  burpsuite, nikto, gobuster, dirb, sqlmap  — Web
  john, hydra, openssl                       — Passwörter
  aircrack-ng                                — WLAN
  metasploit-framework (msfconsole)          — Framework

SYSTEM & NETZ:
  ip a                — Interfaces
  ss -tlnp            — Lauschende Ports
  systemctl status ssh — Service-Status

Übungen stehen in ~/kali-kurs/uebungen/
KRUS

chmod -R 755 "$KURS_DIR"
find "$KURS_DIR" -type f -name '*.txt' -exec chmod 644 {} +

# Aufgaben-Templates
for i in 1 2 3 4 5; do
  case $i in
    1) title="Informationsbeschaffung (Recon)";;
    2) title="Portscan";;
    3) title="Netzwerkverkehr analysieren";;
    4) title="Webanwendungen prüfen";;
    5) title="Passwörter und Hashes";;
  esac

  cat > "$KURS_DIR/uebungen/0$i-*/aufgaben.txt" <<EOF
ÜBUNG $i – $title
$(printf '=%.0s' {1..50})

Lernziel:
  [Hier steht das Lernziel]

Nur auf freigegebenen Zielen arbeiten!

Werkzeuge: [Siehe LIES_MICH.txt]
Vorgehen: [Schritt-für-Schritt-Aufgaben]
EOF
done
