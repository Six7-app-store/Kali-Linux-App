packer {
  required_plugins {
    openstack = {
      source  = "github.com/hashicorp/openstack"
      version = "~> 1"
    }
  }
}

source "openstack" "image" {
  cloud             = "openstack"
  image_name        = var.image_name
  source_image_name = var.source_image_name
  flavor            = var.flavor
  networks          = var.networks
  security_groups   = var.security_groups

  # Eigener Build-Benutzer statt des Standardbenutzers des Images.
  #
  # Welcher Standardbenutzer im Debian-Image steckt, ist nicht dokumentiert -
  # "debian" wurde abgelehnt. Passwort-Login bietet der sshd des Images gar nicht
  # an (nur "publickey"), ein Build-Passwort ist also wirkungslos.
  #
  # Was sicher funktioniert: cloud-init hinterlegt Packers temporaeren Schluessel
  # beim Standardbenutzer (und mit Sperr-Hinweis bei root). runcmd kopiert jeden
  # dort gefundenen Schluessel - ohne Optionen wie command="..." - zu "packer".
  # Bis runcmd gelaufen ist, scheitert der Login; Packer versucht es bis
  # ssh_timeout weiter.
  #
  # 05-verify.sh sperrt "packer" und entfernt alle authorized_keys wieder, die
  # cloud-init-Vorlage in terraform/ loescht den Benutzer auf den Studi-VMs.
  ssh_username = "packer"
  user_data    = <<-EOF
    #cloud-config
    users:
      - default
      - name: packer
        shell: /bin/bash
        sudo: "ALL=(ALL) NOPASSWD:ALL"
    runcmd:
      - [sh, -c, "install -d -m 700 /home/packer/.ssh && cat /root/.ssh/authorized_keys /home/*/.ssh/authorized_keys 2>/dev/null | grep -oE '(ssh-(rsa|ed25519)|ecdsa-sha2-nistp[0-9]+) [A-Za-z0-9+/=]+' | sort -u > /home/packer/.ssh/authorized_keys; chown -R packer:packer /home/packer/.ssh; chmod 600 /home/packer/.ssh/authorized_keys"]
  EOF

  ssh_timeout = "20m"
}

build {
  sources = ["source.openstack.image"]

  provisioner "shell" {
    # Jedes Skript wird einzeln hochgeladen und ausgefuehrt. Ein eigener
    # Orchestrator auf der Build-VM waere wirkungslos: Packer laedt nur die
    # hier genannten Dateien hoch, die aufgerufenen Steps laegen also nie
    # neben ihm.
    scripts = [
      "scripts/01-base.sh",
      "scripts/02-desktop.sh",
      "scripts/03-tools.sh",
      "scripts/04-integration.sh",
      "scripts/05-verify.sh",
    ]

    # Der Provisioner laeuft als SSH-Benutzer "packer", nicht als root. Ohne
    # sudo scheitert schon das erste apt-get an fehlenden Rechten. -E haelt
    # DEBIAN_FRONTEND und Co. am Leben.
    execute_command = "sudo -E bash '{{.Path}}'"
  }
}
