# Prüft die Zugangsdaten-Ausgaben ohne OpenStack-Zugang (Provider gemockt).
#
#   cd tofu && tofu init -backend=false && tofu test

mock_provider "openstack" {
  mock_data "openstack_images_image_v2" {
    defaults = {
      id = "00000000-0000-0000-0000-00000000image"
    }
  }
}

mock_provider "random" {}

variables {
  users = {
    "Team #1" = [{ email = "hannah.roth@dhbw.de" }]
  }
}

# Der Provider liefert fixed_ip_v6 mit eckigen Klammern.
run "rdp_ziel_mit_klammern_vom_provider" {
  command = apply

  override_resource {
    target = openstack_compute_instance_v2.shared_vm
    values = {
      network = { fixed_ip_v6 = "[2001:db8::24c]" }
    }
  }

  assert {
    condition     = output.team_vms.shared_vm.users[0].rdp_target == "[2001:db8::24c]:3389"
    error_message = "Die IPv6-Adresse muss genau einmal eingeklammert sein."
  }
  assert {
    condition     = output.user_accounts["Team #1-hannah-roth"].ip == "[2001:db8::24c]"
    error_message = "ip muss die Klammern tragen - der App Store baut daraus ip:port."
  }
}

# Und ohne Klammern, falls eine Provider-Version sie weglässt.
run "rdp_ziel_ohne_klammern_vom_provider" {
  command = apply

  override_resource {
    target = openstack_compute_instance_v2.shared_vm
    values = {
      network = { fixed_ip_v6 = "2001:db8::24c" }
    }
  }

  assert {
    condition     = output.team_vms.shared_vm.users[0].rdp_target == "[2001:db8::24c]:3389"
    error_message = "Auch ohne Klammern vom Provider muss genau ein Paar entstehen."
  }
}

# Die eigene RDP-Gruppe geht per ID an die VM: ein Name ist nicht eindeutig,
# sobald im Projekt eine zweite "kali-user-rdp" steht.
run "rdp_gruppe_per_id" {
  command = apply

  override_resource {
    target = openstack_networking_secgroup_v2.rdp
    values = {
      id = "11111111-2222-3333-4444-555555555555"
    }
  }

  assert {
    condition     = contains(openstack_compute_instance_v2.shared_vm.security_groups, "11111111-2222-3333-4444-555555555555")
    error_message = "Die RDP-Gruppe muss per ID an der VM haengen."
  }
  assert {
    condition     = !contains(openstack_compute_instance_v2.shared_vm.security_groups, "kali-user-rdp")
    error_message = "Der Name der RDP-Gruppe darf nicht verwendet werden - er ist nicht eindeutig."
  }
}
