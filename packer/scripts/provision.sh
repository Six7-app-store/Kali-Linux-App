#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Provisioning Script für Golden Kali-Linux Image
# - XFCE-Desktop + XRDP (grafischer Zugang über Port 3389)
# - Kuratierte Auswahl der Kali-Werkzeuge
# - Desktop-Integration unter /etc/skel/ (Starter, MIME-Typen, Autostart)
# - Security-Lernverzeichnis unter /etc/skel/kali-kurs/
# - Idempotent, reproduzierbar, CI/CD-tauglich
# -----------------------------------------------------------------------------

export DEBIAN_FRONTEND=noninteractive

echo "Warte auf cloud-init (sofern vorhanden)..."
cloud-init status --wait || true

# =============================================================================
# debconf ruhigstellen
# Ohne das bleibt der Build bei der Wireshark-Frage "Should non-superusers be
# able to capture packets?" stehen, bis Packer nach Timeout abbricht.
# =============================================================================
echo "Stelle debconf auf nicht-interaktiv..."
echo 'debconf debconf/frontend select Noninteractive' | sudo debconf-set-selections
echo 'wireshark-common wireshark-common/install-setuid boolean true' | sudo debconf-set-selections

echo "System aktualisieren..."
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get -y upgrade

echo "Installiere minimale Basis-Tools..."
sudo apt-get install -y --no-install-recommends \
  curl \
  ca-certificates \
  gnupg \
  openssl \
  tree \
  git

# =============================================================================
# Kali-Werkzeuge und Desktop
#
# kali-linux-headless bringt den Grundstock der Kali-Werkzeuge ohne GUI mit,
# kali-desktop-xfce den Desktop samt Kali-Branding (Theme, Hintergrundbild,
# Panel-Layout kommen von dort — deshalb wird hier nichts davon überschrieben).
#
# Metapakete brauchen ihre Recommends, deshalb hier KEIN
# --no-install-recommends. Wenn der Build zu lange dauert (der App Store
# bricht nach einer Stunde hart ab), ist kali-linux-headless die erste
# Stellschraube: durch eine explizite Paketliste ersetzen.
# =============================================================================
echo "Installiere Kali-Grundsystem (headless)..."
sudo apt-get install -y kali-linux-headless

echo "Installiere XFCE-Desktop..."
sudo apt-get install -y kali-desktop-xfce

echo "Installiere kuratierte Werkzeugauswahl für den Kurs..."
sudo apt-get install -y \
  nmap \
  wireshark \
  burpsuite \
  metasploit-framework \
  john \
  hydra \
  sqlmap \
  gobuster \
  netcat-traditional \
  aircrack-ng \
  dirb \
  nikto \
  wordlists

echo "Installiere Desktop-Anwendungen..."
sudo apt-get install -y \
  firefox-esr \
  xfce4-terminal \
  thunar \
  mousepad \
  xdg-user-dirs

# =============================================================================
# XRDP
# =============================================================================
echo "Installiere XRDP..."
sudo apt-get install -y xrdp xorgxrdp dbus-x11

# XRDP muss auf IPv6 lauschen. Im DHBWV6-Netz bekommt die VM nur eine private
# NAT-IPv4 (10.200.x.x); öffentlich erreichbar ist ausschliesslich IPv6.
# Mit dem Default "port=3389" bindet xrdp auf 0.0.0.0 — der Desktop waere dann
# von aussen nicht erreichbar, obwohl der Dienst laeuft.
echo "Konfiguriere XRDP für IPv6..."
sudo sed -i 's|^port=.*|port=tcp6://:3389|' /etc/xrdp/xrdp.ini
if grep -q '^#\?enable_ipv6=' /etc/xrdp/xrdp.ini; then
  sudo sed -i 's|^#\?enable_ipv6=.*|enable_ipv6=true|' /etc/xrdp/xrdp.ini
else
  sudo sed -i '/^\[Globals\]/a enable_ipv6=true' /etc/xrdp/xrdp.ini
fi

# Dual-Stack-Socket explizit erlauben, damit "tcp6://" auch IPv4 mitnimmt.
printf 'net.ipv6.bindv6only = 0\n' \
  | sudo tee /etc/sysctl.d/60-xrdp-dualstack.conf > /dev/null

# Sitzungsgrenzen: ohne das sammeln sich getrennte Sessions an und fressen den
# RAM der gemeinsamen VM. KillDisconnected=false laesst eine kurz unterbrochene
# Verbindung weiterlaufen, das Zeitlimit raeumt sie spaeter trotzdem ab.
echo "Setze XRDP-Sitzungsgrenzen..."
sudo sed -i \
  -e 's|^MaxSessions=.*|MaxSessions=50|' \
  -e 's|^KillDisconnected=.*|KillDisconnected=false|' \
  -e 's|^DisconnectedTimeLimit=.*|DisconnectedTimeLimit=3600|' \
  -e 's|^IdleTimeLimit=.*|IdleTimeLimit=0|' \
  /etc/xrdp/sesman.ini

# Sitzungsstart: fest auf XFCE. /etc/X11/Xsession wuerde sonst je nach
# installierten Sessions etwas anderes waehlen.
echo "Setze XFCE als XRDP-Sitzung..."
sudo tee /etc/xrdp/startwm.sh > /dev/null << 'EOF'
#!/bin/sh
# Startet die XFCE-Sitzung fuer eingehende RDP-Verbindungen.

if [ -r /etc/default/locale ]; then
  . /etc/default/locale
  export LANG LANGUAGE
fi

exec /usr/bin/startxfce4
EOF
sudo chmod 755 /etc/xrdp/startwm.sh

# xrdp braucht Lesezugriff auf das TLS-Zertifikat, sonst faellt die Verbindung
# auf eine Fehlermeldung im Client zurueck.
echo "Erlaube xrdp den Zugriff auf ssl-cert..."
sudo adduser xrdp ssl-cert || true

# --- Polkit: Passwortabfragen in der RDP-Sitzung unterdruecken ---------------
# Ohne diese Regeln begruesst XFCE jeden Studierenden beim Login mit drei
# Authentifizierungsdialogen (Farbprofil, Netzwerk, Paketverwaltung), fuer die
# in einer RDP-Sitzung ohnehin niemand zustaendig ist.
echo "Lege Polkit-Regeln für die Desktop-Sitzung an..."
sudo mkdir -p /etc/polkit-1/rules.d
sudo tee /etc/polkit-1/rules.d/49-kali-desktop.rules > /dev/null << 'EOF'
// Farbprofil-Verwaltung: in einer RDP-Sitzung ohne Belang.
polkit.addRule(function (action, subject) {
    if (action.id.indexOf("org.freedesktop.color-manager.") === 0) {
        return polkit.Result.YES;
    }
});

// Netzwerk- und Paketquellen-Aktionen fuer Mitglieder der sudo-Gruppe.
polkit.addRule(function (action, subject) {
    if ((action.id.indexOf("org.freedesktop.NetworkManager.") === 0 ||
         action.id === "org.freedesktop.packagekit.system-sources-refresh") &&
        subject.isInGroup("sudo")) {
        return polkit.Result.YES;
    }
});
EOF

# Aeltere polkit-Versionen lesen rules.d nicht. Die .pkla-Variante kostet
# nichts und faengt diesen Fall ab.
sudo mkdir -p /etc/polkit-1/localauthority/50-local.d
sudo tee /etc/polkit-1/localauthority/50-local.d/49-kali-desktop.pkla > /dev/null << 'EOF'
[Farbprofile ohne Nachfrage]
Identity=unix-group:sudo
Action=org.freedesktop.color-manager.*
ResultAny=no
ResultInactive=no
ResultActive=yes
EOF

echo "Aktiviere XRDP-Dienste..."
sudo systemctl enable xrdp
sudo systemctl enable xrdp-sesman

# SSH-Passwort-Authentifizierung vorbereiten (für cloud-init)
# Drop-in unter sshd_config.d/ — überschreibt nicht die Hauptdatei
echo "Bereite SSH für Passwort-Auth vor..."
sudo mkdir -p /etc/ssh/sshd_config.d
printf 'PasswordAuthentication yes\n' \
  | sudo tee /etc/ssh/sshd_config.d/60-password-auth.conf > /dev/null

# =============================================================================
# Hilfsskripte für die Desktop-Starter
#
# .desktop-Dateien kennen keine Shell-Expansion — "Exec=thunar $HOME/kali-kurs"
# wuerde wortwoertlich nach einem Ordner namens "$HOME" suchen. Deshalb je ein
# kleines Skript, das den Pfad zur Laufzeit selbst aufloest.
# =============================================================================
echo "Lege Hilfsskripte an..."

sudo tee /usr/local/bin/kali-kurs-oeffnen > /dev/null << 'EOF'
#!/bin/sh
exec thunar "$HOME/kali-kurs"
EOF

sudo tee /usr/local/bin/kali-kurs-lies-mich > /dev/null << 'EOF'
#!/bin/sh
exec mousepad "$HOME/kali-kurs/LIES_MICH.txt"
EOF

# Beim ersten Login die Kurzanleitung zeigen, danach nie wieder.
sudo tee /usr/local/bin/kali-willkommen > /dev/null << 'EOF'
#!/bin/sh
STAMP="$HOME/.config/kali-willkommen-gesehen"
[ -e "$STAMP" ] && exit 0
mkdir -p "$(dirname "$STAMP")"
touch "$STAMP"
exec mousepad "$HOME/kali-kurs/LIES_MICH.txt"
EOF

sudo chmod 755 \
  /usr/local/bin/kali-kurs-oeffnen \
  /usr/local/bin/kali-kurs-lies-mich \
  /usr/local/bin/kali-willkommen

# =============================================================================
# Desktop-Integration unter /etc/skel/
# Alles hier drin wird beim Anlegen eines Kontos in das neue Home kopiert —
# jeder Studierende startet damit in einer fertig eingerichteten Sitzung.
# =============================================================================
echo "Richte Desktop-Integration ein..."

SKEL="/etc/skel"
sudo mkdir -p \
  "${SKEL}/Desktop" \
  "${SKEL}/.config/autostart" \
  "${SKEL}/.config/xfce4/terminal"

# XDG-Verzeichnisse fest verdrahten. Sonst benennt xdg-user-dirs den Ordner je
# nach Systemsprache in "Schreibtisch" um und die Starter landen im Nirgendwo.
sudo tee "${SKEL}/.config/user-dirs.dirs" > /dev/null << 'EOF'
XDG_DESKTOP_DIR="$HOME/Desktop"
XDG_DOWNLOAD_DIR="$HOME/Downloads"
XDG_DOCUMENTS_DIR="$HOME/Documents"
EOF
printf 'enabled=False\n' | sudo tee /etc/xdg/user-dirs.conf > /dev/null

# XFCE-Sitzung auch fuer Zugaenge, die nicht ueber startwm.sh laufen.
printf '#!/bin/sh\nexec /usr/bin/startxfce4\n' \
  | sudo tee "${SKEL}/.xsession" > /dev/null
sudo chmod 755 "${SKEL}/.xsession"

# --- Desktop-Starter ---------------------------------------------------------
sudo tee "${SKEL}/Desktop/kurs-uebungen.desktop" > /dev/null << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Kurs-Übungen
Comment=Öffnet das Verzeichnis mit den Übungsaufgaben
Exec=kali-kurs-oeffnen
Icon=folder-documents
Terminal=false
Categories=Education;
EOF

sudo tee "${SKEL}/Desktop/kurs-anleitung.desktop" > /dev/null << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Kurzanleitung
Comment=Befehlsreferenz und Hinweise zum Kurs
Exec=kali-kurs-lies-mich
Icon=text-x-generic
Terminal=false
Categories=Education;
EOF

sudo tee "${SKEL}/Desktop/terminal.desktop" > /dev/null << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Terminal
Comment=Kali-Terminal öffnen
Exec=xfce4-terminal
Icon=utilities-terminal
Terminal=false
Categories=System;TerminalEmulator;
EOF

sudo tee "${SKEL}/Desktop/firefox.desktop" > /dev/null << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Firefox
Comment=Webbrowser
Exec=firefox-esr %u
Icon=firefox-esr
Terminal=false
Categories=Network;WebBrowser;
EOF

sudo tee "${SKEL}/Desktop/wireshark.desktop" > /dev/null << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Wireshark
Comment=Netzwerkverkehr aufzeichnen und analysieren
Exec=wireshark
Icon=wireshark
Terminal=false
Categories=Network;Monitor;
EOF

sudo tee "${SKEL}/Desktop/burpsuite.desktop" > /dev/null << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Burp Suite
Comment=Web-Proxy zur Analyse von HTTP-Verkehr
Exec=burpsuite
Icon=burpsuite
Terminal=false
Categories=Network;Security;
EOF

# XFCE zeigt Starter ohne Ausfuehrungsrecht als "nicht vertrauenswuerdig" an
# und weigert sich, sie zu oeffnen.
sudo chmod 755 "${SKEL}"/Desktop/*.desktop

# --- Autostart ---------------------------------------------------------------
sudo tee "${SKEL}/.config/autostart/willkommen.desktop" > /dev/null << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Willkommen
Comment=Zeigt die Kurzanleitung beim ersten Login
Exec=kali-willkommen
Icon=text-x-generic
Terminal=false
X-GNOME-Autostart-enabled=true
EOF

# --- Dateizuordnungen --------------------------------------------------------
# Doppelklick auf eine Aufgabendatei soll einen Editor oeffnen, auf eine
# Mitschnittdatei Wireshark.
sudo tee "${SKEL}/.config/mimeapps.list" > /dev/null << 'EOF'
[Default Applications]
text/plain=org.xfce.mousepad.desktop;mousepad.desktop;
text/csv=org.xfce.mousepad.desktop;mousepad.desktop;
text/html=firefox-esr.desktop;
application/vnd.tcpdump.pcap=wireshark.desktop;
application/x-pcapng=wireshark.desktop;
inode/directory=thunar.desktop;
EOF

# --- Terminal-Voreinstellungen ----------------------------------------------
sudo tee "${SKEL}/.config/xfce4/terminal/terminalrc" > /dev/null << 'EOF'
[Configuration]
FontName=Monospace 11
ScrollingLines=10000
MiscAlwaysShowTabs=FALSE
MiscConfirmClose=FALSE
MiscMenubarDefault=TRUE
MiscToolbarDefault=FALSE
EOF

# =============================================================================
# Security-Lernverzeichnis
# Wird unter /etc/skel/ abgelegt -> automatisch in jeden neuen Home-Ordner.
# Die Inhalte sind bewusst knapp gehalten: sie benennen die Werkzeuge und
# verweisen auf deren eingebaute Hilfe. Die eigentlichen Aufgaben und
# Freigaben kommen vom Dozenten.
# =============================================================================
echo "Erstelle Security-Lernverzeichnis..."

KURS_DIR="/etc/skel/kali-kurs"
sudo mkdir -p \
  "${KURS_DIR}/uebungen/01-recon" \
  "${KURS_DIR}/uebungen/02-portscan" \
  "${KURS_DIR}/uebungen/03-traffic-analyse" \
  "${KURS_DIR}/uebungen/04-web-schwachstellen" \
  "${KURS_DIR}/uebungen/05-passwoerter"

# --- Kurzanleitung (LIES_MICH.txt) ------------------------------------------
sudo tee "${KURS_DIR}/LIES_MICH.txt" > /dev/null << 'EOF'
╔══════════════════════════════════════════════════════════════════════════════╗
║                    KALI LINUX – KURZANLEITUNG                              ║
╚══════════════════════════════════════════════════════════════════════════════╝

Willkommen auf deiner Kali-VM!
Du arbeitest auf einem grafischen Desktop, den du über Remotedesktop (RDP)
erreichst. Dieses Verzeichnis enthält Übungsaufgaben und Hinweise.

  Kurs-Übungen        → Starter auf dem Desktop, oder: tree ~/kali-kurs
  Kurzanleitung       → Starter auf dem Desktop, oder: cat ~/kali-kurs/LIES_MICH.txt

──────────────────────────────────────────────────────────────────────────────
 SPIELREGELN – BITTE ZUERST LESEN
──────────────────────────────────────────────────────────────────────────────
  Die Werkzeuge auf diesem System sind für Sicherheitsanalysen gedacht. Sie
  auf fremde Systeme ohne Erlaubnis des Betreibers anzuwenden, ist in
  Deutschland strafbar (§ 202a-c, § 303a-b StGB) — auch wenn nichts kaputtgeht.

  In diesem Kurs arbeitest du ausschliesslich auf Zielen, die der Dozent
  ausdrücklich freigegeben hat (z. B. diese VM selbst oder eine bereitgestellte
  Übungsumgebung). Alles andere ist tabu. Im Zweifel: nachfragen, nicht
  ausprobieren.

──────────────────────────────────────────────────────────────────────────────
 DESKTOP & SITZUNG
──────────────────────────────────────────────────────────────────────────────
  Abmelden              Anwendungen → Abmelden (schliesst die Sitzung sauber)
  Terminal öffnen       Starter auf dem Desktop, oder Strg+Alt+T
  Dateimanager          Thunar — Starter "Kurs-Übungen" auf dem Desktop
  Editor                Mousepad (grafisch), nano oder vim (Terminal)

  Hinweis: Du teilst diese VM mit anderen Kursteilnehmenden. Beende deine
  Sitzung, wenn du fertig bist — jede offene Sitzung belegt Arbeitsspeicher.

──────────────────────────────────────────────────────────────────────────────
 WERKZEUGE IN DIESEM KURS
──────────────────────────────────────────────────────────────────────────────
  Jedes Werkzeug bringt eine eingebaute Hilfe mit. Ruf sie auf, bevor du
  loslegst — dort stehen die Optionen, die zur jeweiligen Aufgabe passen:

    <werkzeug> --help          Kurzhilfe
    man <werkzeug>             ausführliche Handbuchseite

  Netzwerk & Analyse    nmap, wireshark, tcpdump, netcat
  Web                   burpsuite, nikto, gobuster, dirb, sqlmap
  Passwörter & Hashes   john, hydra, openssl
  WLAN                  aircrack-ng
  Framework             metasploit-framework (msfconsole)

  Wörterlisten für Übungen liegen unter /usr/share/wordlists/.

──────────────────────────────────────────────────────────────────────────────
 SYSTEM & NETZ
──────────────────────────────────────────────────────────────────────────────
  ip a                 Interfaces und IP-Adressen anzeigen
  ss -tlnp             Lauschende TCP-Ports mit zugehörigem Prozess
  systemctl status ssh Status eines Dienstes
  journalctl -n 50     Letzte 50 Systemlog-Einträge

──────────────────────────────────────────────────────────────────────────────
 Tipp: TAB vervollständigt Befehle und Pfade, die Pfeiltasten holen frühere
 Befehle zurück. Details zu jeder Übung stehen in den Ordnern unter uebungen/.
──────────────────────────────────────────────────────────────────────────────
EOF

# --- Übungsübersichten -------------------------------------------------------
# Bewusst als Lernziele + Werkzeugverweis formuliert. Die konkreten Ziele und
# Schritt-für-Schritt-Aufgaben stellt der Dozent in der Lehrveranstaltung.

sudo tee "${KURS_DIR}/uebungen/01-recon/aufgaben.txt" > /dev/null << 'EOF'
ÜBUNG 1 – Informationsbeschaffung (Recon)
==========================================

Lernziel:
  Verstehen, welche Informationen über ein System öffentlich verfügbar sind
  und mit welchen Werkzeugen man sie strukturiert erhebt.

Nur auf vom Dozenten freigegebenen Zielen arbeiten.

Werkzeuge:
  whois, dig, host   – DNS- und Registrierungsdaten
  curl -I            – HTTP-Header eines Servers lesen

Vorgehen:
  Ruf zu jedem Werkzeug zuerst "man <werkzeug>" oder "<werkzeug> --help" auf
  und notiere, welche Angaben du über das freigegebene Ziel zusammentragen
  kannst. Halte deine Ergebnisse in einer Textdatei in diesem Ordner fest.
EOF

sudo tee "${KURS_DIR}/uebungen/02-portscan/aufgaben.txt" > /dev/null << 'EOF'
ÜBUNG 2 – Portscan
===================

Lernziel:
  Offene Ports und dahinter laufende Dienste einer Maschine ermitteln und die
  Ausgabe eines Scanners lesen.

Ziel: diese VM selbst (localhost) oder ein vom Dozenten freigegebenes System.

Werkzeug:
  nmap  – "man nmap" zeigt die Scan-Typen und Ausgabeoptionen.

Vorgehen:
  Scanne zunächst localhost und ordne den offenen Ports die Dienste zu, die du
  auf dem System kennst (z. B. SSH auf 22, RDP auf 3389). Vergleiche das
  Ergebnis mit "ss -tlnp".
EOF

sudo tee "${KURS_DIR}/uebungen/03-traffic-analyse/aufgaben.txt" > /dev/null << 'EOF'
ÜBUNG 3 – Netzwerkverkehr analysieren
======================================

Lernziel:
  Netzwerkpakete mitschneiden und in Wireshark auswerten.

Werkzeuge:
  tcpdump    – Mitschnitt im Terminal ("man tcpdump")
  wireshark  – grafische Analyse (Starter auf dem Desktop)

Vorgehen:
  Zeichne den Verkehr auf, der entsteht, wenn du selbst eine Verbindung zu
  diesem System aufbaust, und finde die zugehörigen Pakete in Wireshark wieder.
  Übe die Anzeigefilter (z. B. nach Protokoll oder Port).
EOF

sudo tee "${KURS_DIR}/uebungen/04-web-schwachstellen/aufgaben.txt" > /dev/null << 'EOF'
ÜBUNG 4 – Webanwendungen prüfen
================================

Lernziel:
  Eine Webanwendung systematisch auf bekannte Schwachstellenklassen prüfen und
  die Befunde einordnen.

Ziel: ausschliesslich die vom Dozenten bereitgestellte Übungs-Webanwendung.

Werkzeuge:
  nikto, gobuster, dirb   – Server und Verzeichnisse untersuchen
  burpsuite               – HTTP-Verkehr mitlesen (Desktop-Starter)

Vorgehen:
  Arbeite dich über die eingebaute Hilfe der Werkzeuge in ihre Grundfunktionen
  ein und dokumentiere, welche Auffälligkeiten du an der Übungsanwendung
  findest. Bewerte jeden Befund: echtes Problem oder Fehlalarm?
EOF

sudo tee "${KURS_DIR}/uebungen/05-passwoerter/aufgaben.txt" > /dev/null << 'EOF'
ÜBUNG 5 – Passwörter und Hashes verstehen
==========================================

Lernziel:
  Verstehen, wie Passwörter als Hash gespeichert werden und warum die Wahl des
  Verfahrens und eines Salts die Sicherheit bestimmt.

Werkzeuge:
  openssl passwd   – einen Hash zu einem Passwort erzeugen ("man openssl-passwd")
  john             – Formatliste über "john --list=formats"

Vorgehen:
  Erzeuge mit openssl Hashes desselben Passworts mit verschiedenen Verfahren
  und vergleiche sie. Halte fest, welche Rolle der Salt spielt. Bearbeite den
  praktischen Teil nur mit Hashes, die der Dozent bereitstellt.
EOF

# Lesbar für alle, schreiben nur root
sudo chmod -R 755 "${KURS_DIR}"
sudo find "${KURS_DIR}" -type f -name '*.txt' -exec chmod 644 {} +

echo "Prüfe Versionen..."
xrdp --version || true
nmap --version | head -1 || true

echo "Cleanup: apt-Cache & Listen entfernen..."
sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/*

echo "Setze machine-id zurück..."
sudo truncate -s 0 /etc/machine-id
sudo rm -f /var/lib/dbus/machine-id || true

echo "Provisioning abgeschlossen."
