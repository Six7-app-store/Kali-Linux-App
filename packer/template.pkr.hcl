packer {
  required_plugins {
    openstack = {
      source  = "github.com/hashicorp/openstack"
      version = "~> 1"
    }
  }
}

locals {
  # Einmalpasswort fuer den Build-Benutzer, bei jedem Build neu.
  build_password = uuidv4()
}

source "openstack" "image" {
  cloud             = "openstack"
  image_name        = var.image_name
  source_image_name = var.source_image_name
  flavor            = "gp1.medium"
  networks          = var.networks
  security_groups   = var.security_groups

  # Eigener Build-Benutzer statt des Standardbenutzers des Images.
  #
  # Welcher Benutzer im Debian-Image steckt, ist nicht dokumentiert - "debian"
  # (offizielle Cloud-Images) wurde abgelehnt ("unable to authenticate").
  # cloud-init legt "packer" deshalb beim ersten Start selbst an; das klappt mit
  # jedem cloud-init-Image. 05-verify.sh sperrt den Benutzer wieder, die
  # cloud-init-Vorlage in terraform/ loescht ihn auf den Studi-VMs.
  ssh_username = "packer"
  ssh_password = local.build_password
  user_data    = <<-EOF
    #cloud-config
    ssh_pwauth: true
    users:
      - default
      - name: packer
        shell: /bin/bash
        sudo: "ALL=(ALL) NOPASSWD:ALL"
        lock_passwd: false
    chpasswd:
      expire: false
      users:
        - name: packer
          password: "${local.build_password}"
          type: text
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
