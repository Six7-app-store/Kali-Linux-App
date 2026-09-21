#cloud-config

# SSH mit Passwort-Auth aktivieren
ssh_pwauth: true

# Pakete installieren. Der Desktop (XFCE, XRDP) und die Werkzeuge sind bereits
# im Image; hier nur ein paar Kleinigkeiten fuer den ersten Boot.
packages:
  - curl
  - wget
  - git
  - htop
  - nano
  - vim
  - net-tools

# Gruppen für jedes Team erstellen.
# jsonencode() setzt jeden Wert in Anfuehrungszeichen: ohne das wuerde YAML
# "Team #1" am Leerzeichen-# abschneiden und alle Teams zu "Team" verschmelzen.
groups:
%{ for group in unique_groups ~}
  - ${jsonencode(group)}
%{ endfor ~}

# Benutzer erstellen.
# Neben der Teamgruppe kommt jeder Nutzer in "sudo" (fuer die Polkit-Regeln des
# Desktops) und "wireshark" (Mitschnitt ohne root).
users:
%{ for idx, user in all_users ~}
  - name: ${jsonencode(user.username)}
    shell: /bin/bash
    sudo: ['ALL=(ALL) ALL']
    groups: [${jsonencode(user.group)}, "sudo", "wireshark"]
    lock_passwd: false
%{ endfor ~}

# SSH-Konfiguration in separate Datei.
# (Die XRDP-Sitzungsgrenzen stehen bereits im Image, siehe provision.sh —
# hier nichts doppeln.)
write_files:
  - path: /etc/ssh/sshd_config.d/99-custom.conf
    content: |
      PasswordAuthentication yes
      PubkeyAuthentication yes
      PermitRootLogin no
      UsePAM yes
    permissions: '0644'

# Setup-Befehle
# Passwoerter zwingend ueber jsonencode(): ein Passwort, das mit ! @ % oder *
# beginnt, ist als unquotierter YAML-Skalar ein Syntaxfehler und liesse das
# komplette user-data scheitern - die VM liefe dann ganz ohne Benutzer.
chpasswd:
  expire: false
  users:
%{ for idx, user in all_users ~}
    - name: ${jsonencode(user.username)}
      password: ${jsonencode(passwords[idx])}
      type: text
%{ endfor ~}

runcmd:
  - systemctl restart ssh

  # Firewall: erst SSH und RDP freigeben, dann einschalten (nicht umgekehrt)
  - ufw allow OpenSSH
  - ufw allow 3389/tcp
  - ufw --force enable

  # Desktop-Dienst starten. enable --now zieht den Dienst gleich hoch, der
  # anschliessende restart nimmt die frisch angelegten Benutzer mit.
  - systemctl enable --now xrdp xrdp-sesman
  - systemctl restart xrdp

  # Setup-Log (OHNE Passwörter aus Sicherheitsgründen)
  - |
    cat >> /var/log/setup-complete.log <<EOF
    ================================================
    Setup abgeschlossen: $(date)
    ================================================
    Teams: ${join(", ", unique_teams)}
    Benutzer erstellt: ${length(all_users)}
    ================================================
    EOF

# Abschlussnachricht
final_message: |
  ================================================
  Kali Multi-User Desktop bereit!
  ================================================
  Teams: ${join(", ", unique_teams)}
  Benutzer: ${length(all_users)}

  Zugang per Remotedesktop (RDP):
    Windows: Remotedesktopverbindung (mstsc) -> [<vm-ipv6>]:3389
  Terminal-Zugang alternativ:
    ssh <username>@<vm-ipv6>
  ================================================
