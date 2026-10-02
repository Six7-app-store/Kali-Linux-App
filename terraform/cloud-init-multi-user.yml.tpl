#cloud-config

ssh_pwauth: true

# Je ein Listeneintrag pro Paket. Eine einzelne Zeile mit Leerzeichen waere
# EIN Paketname - apt suchte dann nach "curl wget git ..." und schluege fehl.
packages:
  - curl
  - wget
  - git
  - htop
  - nano
  - vim
  - net-tools

groups:
%{ for group in unique_groups ~}
  - ${jsonencode(group)}
%{ endfor ~}

users:
%{ for idx, user in all_users ~}
  - name: ${jsonencode(user.username)}
    shell: /bin/bash
    sudo: ['ALL=(ALL) ALL']
    groups: [${jsonencode(user.group)}, "sudo", "wireshark"]
    lock_passwd: false
%{ endfor ~}

write_files:
  - path: /etc/ssh/sshd_config.d/99-custom.conf
    content: |
      PasswordAuthentication yes
      PubkeyAuthentication yes
      PermitRootLogin no
      UsePAM yes
    permissions: '0644'

chpasswd:
  expire: false
  users:
%{ for idx, user in all_users ~}
    - name: ${jsonencode(user.username)}
      password: ${jsonencode(passwords[idx])}
      type: text
%{ endfor ~}

# Keine ufw-Regeln: ufw ist im Kali-Cloud-Image nicht installiert, die Befehle
# schlugen hier still fehl. Gefiltert wird in OpenStack ohnehin eine Ebene
# tiefer durch die Security Groups (SSH via shared_secgroup_id, RDP via der
# App-eigenen Gruppe in main.tf) - eine Host-Firewall waere nur eine zweite,
# unabhaengig zu pflegende Wahrheit.
runcmd:
  # Build-Benutzer aus dem Packer-Image (dort schon gesperrt) endgueltig entfernen.
  - userdel -r packer 2>/dev/null || true
  - systemctl restart ssh || { echo "SSH Restart fehlgeschlagen" >> /var/log/setup-complete.log; exit 1; }
  - systemctl enable --now xrdp xrdp-sesman || { echo "XRDP enable fehlgeschlagen" >> /var/log/setup-complete.log; exit 1; }
  - systemctl restart xrdp || { echo "XRDP restart fehlgeschlagen" >> /var/log/setup-complete.log; exit 1; }
  - |
    [ "$(systemctl is-active ssh)" = "active" ] || { echo "SSH nicht aktiv" >> /var/log/setup-complete.log; exit 1; }
  - |
    [ "$(systemctl is-active xrdp)" = "active" ] || { echo "XRDP nicht aktiv" >> /var/log/setup-complete.log; exit 1; }
  - |
    # Nicht nur "laeuft der Dienst", sondern "lauscht er auf IPv6". Ein auf
    # IPv4 gebundener XRDP waere im DHBWV6-Netz nicht erreichbar.
    ss -tln | grep -q '\[::\]:3389' || { echo "XRDP lauscht nicht auf IPv6:3389" >> /var/log/setup-complete.log; exit 1; }
  - |
    cat >> /var/log/setup-complete.log <<'SETUPLOG'
    ================================================
    Setup erfolgreich
    ================================================
    SETUPLOG
  - date >> /var/log/setup-complete.log

final_message: |
  ================================================
  Kali-Desktop bereit!
  ================================================
  Teams: ${join(", ", unique_teams)}
  Nutzer: ${length(all_users)}
  RDP: [<ipv6>]:3389
  SSH: ssh <user>@<ipv6>
  ================================================
