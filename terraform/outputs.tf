
############################
# [CONTRACT] User Accounts Output
############################

locals {
  # Einziges oeffentlich erreichbares Ziel der VM. Es gibt bewusst keine
  # Floating IP (siehe main.tf).
  vm_ipv6 = openstack_compute_instance_v2.shared_vm.network[0].fixed_ip_v6
}

output "user_accounts" {
  description = "[CONTRACT] User accounts mit Login-Informationen"
  sensitive   = true # Enthält Passwörter
  value = {
    for i in range(length(local.all_users)) : local.user_ids[i] => {
      type     = "password"
      ip       = local.vm_ipv6
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
      fixed_ip_v6   = local.vm_ipv6
      users = [for i in range(length(local.all_users)) : {
        username = local.usernames[i]
        team     = local.all_users[i].team

        # RDP-Ziel für die Windows-Remotedesktopverbindung. Die eckigen Klammern
        # um die IPv6-Adresse sind Pflicht, sonst liest der Client den letzten
        # ":" als Port-Trenner.
        rdp_target = "[${local.vm_ipv6}]:3389"

        # Terminal-Zugang bleibt dokumentiert.
        ssh_command = "ssh ${local.usernames[i]}@${local.vm_ipv6}"
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
