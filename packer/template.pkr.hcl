packer {
  required_plugins {
    openstack = {
      source  = "github.com/hashicorp/openstack"
      version = "~> 1"
    }
  }
}

source "openstack" "image" {
  cloud           = "openstack"
  image_name      = var.image_name
  flavor          = "gp1.medium"
  networks        = var.networks
  security_groups = var.security_groups

  # Glance laedt das Basis-Image selbst aus dem Internet (Image-Import
  # "web-download"); Packer wartet, bis es aktiv ist, und loescht es nach dem
  # Build wieder. Schliesst source_image_name aus. Voraussetzung: die
  # OpenStack-Installation erlaubt web-download.
  external_source_image_url    = var.source_image_url
  external_source_image_format = "qcow2"

  # Standardbenutzer der Debian-Cloud-Images.
  ssh_username = "debian"

  # Erststart inklusive Image-Import dauert laenger als bei einem fertigen
  # Glance-Image.
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
