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
  flavor            = "gp1.medium"
  networks          = var.networks
  security_groups   = var.security_groups

  # Standardbenutzer der offiziellen Debian-Cloud-Images.
  ssh_username = "debian"

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

    # Der Provisioner laeuft als SSH-Benutzer "kali", nicht als root. Ohne
    # sudo scheitert schon das erste apt-get an fehlenden Rechten. -E haelt
    # DEBIAN_FRONTEND und Co. am Leben.
    execute_command = "sudo -E bash '{{.Path}}'"
  }
}
