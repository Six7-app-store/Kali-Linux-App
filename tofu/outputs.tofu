############################
# [CONTRACT] User Accounts Output
############################

locals {
  # Einziges oeffentlich erreichbares Ziel der VM. Es gibt bewusst keine
  # Floating IP (siehe main.tofu). Bei ipv6 die IPv6, bei ipv4 die feste
  # IPv4, bei dual die IPv4 der zweiten Schnittstelle, weil sie mehr
  # Heimnetze erreicht.
  #
  # IPv6 genau einmal in eckigen Klammern: der Provider liefert fixed_ip_v6
  # schon als "[2001:...]", und der App Store setzt ip und port ungeprueft zu
  # "ip:port" zusammen - ohne Klammern laese der Client den letzten ":" der
  # Adresse als Port-Trenner. trim() macht das unabhaengig davon, ob eine
  # Provider-Version die Klammern liefert.
  vm_ipv6 = var.ip_mode == "ipv4" ? null : "[${trim(openstack_compute_instance_v2.shared_vm.network[0].fixed_ip_v6, "[]")}]"
  vm_ipv4 = (
    var.ip_mode == "ipv4" ? openstack_compute_instance_v2.shared_vm.network[0].fixed_ip_v4
    : local.dual ? local.secondary_ipv4
    : null
  )
  vm_address = coalesce(local.vm_ipv4, local.vm_ipv6)
}

output "user_accounts" {
  description = "[CONTRACT] User accounts mit Login-Informationen"
  sensitive   = true # Enthält Passwörter
  value = {
    for i in range(length(local.all_users)) : local.user_ids[i] => {
      type     = "password"
      ip       = local.vm_address
      port     = 3389
      username = local.usernames[i]
      auth     = random_password.user_passwords[i].result
      email    = local.emails[i]
      team     = local.all_users[i].team
    }
  }
}

############################
# VM Details
############################

output "team_vms" {
  description = "Details der gemeinsamen VM und aller Benutzer"
  value = {
    shared_vm = {
      instance_id   = openstack_compute_instance_v2.shared_vm.id
      instance_name = openstack_compute_instance_v2.shared_vm.name
      ip_mode       = var.ip_mode
      fixed_ip_v6   = local.vm_ipv6
      fixed_ip_v4   = local.vm_ipv4
      users = [for i in range(length(local.all_users)) : {
        username = local.usernames[i]
        team     = local.all_users[i].team

        # RDP-Ziel für die Windows-Remotedesktopverbindung. Die Klammern um
        # eine IPv6-Adresse bringt local.vm_address schon mit.
        rdp_target = "${local.vm_address}:3389"

        # Terminal-Zugang bleibt dokumentiert.
        ssh_command = "ssh ${local.usernames[i]}@${local.vm_address}"
      }]
    }
  }
}

output "teams_summary" {
  description = "Übersicht: Anzahl VMs und User"
  value = {
    vm_count   = 1
    user_count = length(local.all_users)
    usernames  = local.usernames
    emails     = local.emails
    teams      = local.unique_teams
  }
}
