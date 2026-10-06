#cloud-config

# Kein Image-Build: die VM startet als Debian 13 und richtet sich hier beim
# ersten Start selbst ein (Umstellung auf Kali, Desktop, Werkzeuge, Kursordner).
# Das dauert deutlich laenger als ein Start aus einem fertigen Image; Fortschritt
# in /var/log/kali-app-setup.log, Status in /etc/motd.

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

# "wireshark" fehlt hier absichtlich: die Gruppe entsteht erst mit dem Paket in
# 03-tools.sh. Eine unbekannte Gruppe liesse useradd scheitern und der Account
# wuerde gar nicht angelegt. 05-users.sh traegt die Accounts nach.
users:
%{ for idx, user in all_users ~}
  - name: ${jsonencode(user.username)}
    shell: /bin/bash
    sudo: "ALL=(ALL) ALL"
    groups: [${jsonencode(user.group)}, "sudo"]
    lock_passwd: false
%{ endfor ~}

write_files:
  # 00- statt 99-: sshd nimmt bei doppelten Angaben den ERSTEN Wert, Drop-ins
  # werden alphabetisch gelesen. Ein mitgeliefertes "PasswordAuthentication no"
  # des Basis-Images (z. B. 50-cloud-init.conf) wuerde 99- sonst ueberstimmen.
  - path: /etc/ssh/sshd_config.d/00-kali-app.conf
    content: |
      PasswordAuthentication yes
      PubkeyAuthentication yes
      PermitRootLogin no
      UsePAM yes
    permissions: '0644'
  - path: /etc/motd
    content: |

        ⏳ Diese Kali-VM richtet sich noch ein (Umstellung auf Kali, Desktop,
           Werkzeuge). Remotedesktop geht erst danach.
           Fortschritt: tail -f /var/log/kali-app-setup.log

    permissions: '0644'
  # Einrichtungsskripte aus terraform/scripts/, gzip+base64 wegen des
  # user_data-Limits von 64 KB.
%{ for name, content in scripts ~}
  - path: /opt/kali-app/${name}
    encoding: gz+b64
    content: ${content}
    permissions: '0755'
%{ endfor ~}

chpasswd:
  expire: false
  users:
%{ for idx, user in all_users ~}
    - name: ${jsonencode(user.username)}
      password: ${jsonencode(passwords[idx])}
      type: text
%{ endfor ~}

# Keine ufw-Regeln: gefiltert wird in OpenStack durch die Security Groups (SSH
# via shared_secgroup_id, RDP via der App-eigenen Gruppe in main.tf).
runcmd:
  - ["bash", "/opt/kali-app/setup.sh"%{ for user in all_users ~}, ${jsonencode(user.username)}%{ endfor ~}]

# Einmal neu starten, damit Kernel, systemd und Dienste aus Kali laufen statt
# der Debian-Versionen, die beim Upgrade noch im Speicher waren. Nur wenn die
# Einrichtung durchlief - sonst bleibt die VM fuer die Fehlersuche so stehen.
power_state:
  mode: reboot
  message: "Kali-Einrichtung abgeschlossen, Neustart"
  condition: "test -f /var/lib/kali-app/ready"

final_message: |
  Kali-App: cloud-init fertig nach $UPTIME s.
  Teams: ${join(", ", unique_teams)}
  Nutzer: ${length(all_users)}
