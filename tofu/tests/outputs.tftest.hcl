# Prüft die Zugangsdaten-Ausgaben ohne OpenStack-Zugang (Provider gemockt).
#
#   cd tofu && tofu init -backend=false && tofu test

mock_provider "openstack" {
  mock_data "openstack_images_image_v2" {
    defaults = {
      id = "00000000-0000-0000-0000-00000000image"
    }
  }
  mock_data "openstack_networking_subnet_v2" {
    defaults = {
      cidr       = "141.72.10.0/24"
      gateway_ip = "141.72.10.1"
    }
  }
  mock_resource "openstack_compute_instance_v2" {
    defaults = {
      network = { fixed_ip_v6 = "[2001:db8::24c]", fixed_ip_v4 = "10.200.0.42" }
    }
  }
  mock_resource "openstack_networking_port_v2" {
    defaults = {
      all_fixed_ips = ["141.72.10.7"]
      mac_address   = "fa:16:3e:00:00:07"
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

# Die eigene RDP-Gruppe geht per ID an die VM. Das allein reicht auf newstack
# nicht: Nova loest auch eine ID ueber den Namen auf. Deshalb traegt der Name
# einen Zufallsanhang und ist je Deployment eindeutig.
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

# Der Worker erkennt das Ende der Einrichtung an der Standardzeile von
# cloud-init; nach Kalis Neustart fehlt die systemd-Zeile auf der Konsole.
run "abschlusszeile_fuer_den_worker" {
  command = apply

  assert {
    condition     = startswith(yamldecode(openstack_compute_instance_v2.shared_vm.user_data).final_message, "Cloud-init v. $VERSION finished at $TIMESTAMP.")
    error_message = "final_message muss mit der Standardzeile von cloud-init beginnen, sonst wartet der Worker bis zum Timeout."
  }
}

run "rdp_gruppe_mit_eindeutigem_namen" {
  command = apply

  override_resource {
    target = random_string.secgroup_suffix
    values = {
      result = "x7k2qa"
    }
  }

  assert {
    condition     = openstack_networking_secgroup_v2.rdp.name == "kali-user-rdp-x7k2qa"
    error_message = "Der Name der RDP-Gruppe braucht den Zufallsanhang, sonst kollidieren zwei Deployments im selben Projekt."
  }
}

run "ipv6_ist_standard" {
  command = apply

  assert {
    condition     = keys(openstack_networking_secgroup_rule_v2.rdp) == ["IPv6"] && keys(openstack_networking_secgroup_rule_v2.ssh) == ["IPv6"]
    error_message = "Ohne Auswahl gilt ipv6: RDP und SSH nur fuer IPv6."
  }
  assert {
    condition     = openstack_compute_instance_v2.shared_vm.network[0].uuid == "9b579624-d844-4df3-b38d-89978b31d37d"
    error_message = "ipv6 haengt die VM ins IPv6-Netz."
  }
  assert {
    condition     = !strcontains(openstack_compute_instance_v2.shared_vm.user_data, "/etc/kali-app/secondary-ipv4")
    error_message = "Ohne dual keine Daten fuer eine zweite Schnittstelle."
  }
}

run "zugang_ueber_ipv4" {
  command = apply

  variables {
    ip_mode         = "ipv4"
    network_v4_uuid = "00000000-0000-0000-0000-0000000000v4"
  }

  assert {
    condition     = openstack_compute_instance_v2.shared_vm.network[0].uuid == "00000000-0000-0000-0000-0000000000v4"
    error_message = "ipv4 muss die VM ins IPv4-Netz haengen."
  }
  assert {
    condition     = openstack_networking_secgroup_rule_v2.rdp["IPv4"].remote_ip_prefix == "141.72.0.0/16"
    error_message = "RDP ueber IPv4 bleibt auf Campus und VPN beschraenkt."
  }
  assert {
    condition     = output.user_accounts["Team #1-hannah-roth"].ip == "10.200.0.42"
    error_message = "Die Zugangsdaten muessen die feste IPv4 nennen, ohne Klammern."
  }
  assert {
    condition     = output.team_vms.shared_vm.users[0].rdp_target == "10.200.0.42:3389"
    error_message = "Das RDP-Ziel ist die IPv4 mit Port."
  }
}

run "dual_haengt_ipv4_als_zweite_schnittstelle_an" {
  command = apply

  variables {
    ip_mode         = "dual"
    network_v4_uuid = "00000000-0000-0000-0000-0000000000v4"
  }

  assert {
    condition     = length(openstack_compute_interface_attach_v2.v4) == 1
    error_message = "dual braucht die IPv4-Schnittstelle als zweiten Port."
  }
  assert {
    condition     = toset(keys(openstack_networking_secgroup_rule_v2.rdp)) == toset(["IPv4", "IPv6"])
    error_message = "dual braucht RDP-Regeln fuer beide Familien."
  }
  assert {
    condition     = output.user_accounts["Team #1-hannah-roth"].ip == "141.72.10.7"
    error_message = "Bei dual nennen die Zugangsdaten die IPv4 der zweiten Schnittstelle."
  }
  assert {
    condition     = local.secondary_config == "fa:16:3e:00:00:07 141.72.10.7/24 141.72.10.0/24 141.72.10.1"
    error_message = "08-ipv4.sh braucht MAC, Adresse mit Praefix, Netz und Gateway."
  }
  assert {
    condition     = one([for f in yamldecode(openstack_compute_instance_v2.shared_vm.user_data).write_files : f.content if f.path == "/etc/kali-app/secondary-ipv4"]) == "fa:16:3e:00:00:07 141.72.10.7/24 141.72.10.0/24 141.72.10.1\n"
    error_message = "cloud-init muss die Daten der zweiten Schnittstelle ablegen."
  }
}

run "ipv4_ohne_netz_wird_abgelehnt" {
  command = plan

  variables {
    ip_mode = "ipv4"
  }

  expect_failures = [openstack_compute_instance_v2.shared_vm]
}
