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

  # Das Kali-Cloud-Image hat keinen "ubuntu"-Benutzer.
  ssh_username = "kali"

  # Kali braucht beim Erststart laenger als Ubuntu, bis sshd bereit ist.
  ssh_timeout = "20m"
}

build {
  sources = ["source.openstack.image"]

  provisioner "shell" {
    script = "scripts/provision.sh"
  }
}
