#cloud-config

ssh_pwauth: true

packages:
  - curl wget git htop nano vim net-tools

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

runcmd:
  - systemctl restart ssh || { echo "SSH Restart fehlgeschlagen" >> /var/log/setup-complete.log; exit 1; }
  - ufw allow OpenSSH || { echo "SSH UFW fehlgeschlagen" >> /var/log/setup-complete.log; exit 1; }
  - ufw allow 3389/tcp || { echo "RDP UFW fehlgeschlagen" >> /var/log/setup-complete.log; exit 1; }
  - ufw --force enable || { echo "UFW enable fehlgeschlagen" >> /var/log/setup-complete.log; exit 1; }
  - systemctl enable --now xrdp xrdp-sesman || { echo "XRDP enable fehlgeschlagen" >> /var/log/setup-complete.log; exit 1; }
  - systemctl restart xrdp || { echo "XRDP restart fehlgeschlagen" >> /var/log/setup-complete.log; exit 1; }
  - |
    [ "$(systemctl is-active ssh)" = "active" ] || { echo "SSH nicht aktiv" >> /var/log/setup-complete.log; exit 1; }
  - |
    [ "$(systemctl is-active xrdp)" = "active" ] || { echo "XRDP nicht aktiv" >> /var/log/setup-complete.log; exit 1; }
  - |
    cat >> /var/log/setup-complete.log <<EOF
    ================================================
    Setup erfolgreich: $(date)
    ================================================
    Teams: ${join(", ", unique_teams)}
    Nutzer: ${length(all_users)}
    ================================================
    EOF

final_message: |
  ================================================
  Kali-Desktop bereit!
  ================================================
  Teams: ${join(", ", unique_teams)}
  Nutzer: ${length(all_users)}
  RDP: [<ipv6>]:3389
  SSH: ssh <user>@<ipv6>
  ================================================
