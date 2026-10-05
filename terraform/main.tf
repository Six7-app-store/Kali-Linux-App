terraform {
  required_version = ">= 1.0"

  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.54"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.10"
    }
  }
}

provider "openstack" {
  cloud = "openstack"
  # Auth via OS_CLOUD + clouds.yaml (oder OS_* env vars)
}

############################
# APP-DEFAULTS (vom App-Entwickler vorgegeben)
############################

locals {
  app_name = "kali-user"
  key_pair = "" # Leer = nur Passwort-Auth

  metadata = {}
}

# Keine Floating IP: sie liesse sich in diesem Projekt zwar anlegen, aber nicht
# zuweisen - zwischen VM-Subnetz und externem Netz fehlt der Router
# ("External network ... is not reachable from subnet").
#
# Oeffentlich erreichbar ist die Instanz ueber IPv6; die feste IPv4 im
# DHBWV6-Netz ist eine private NAT-Adresse (10.200.x.x). Deshalb geben die
# outputs fixed_ip_v6 als Verbindungsziel aus.

############################
# USER MANAGEMENT (CONTRACT)
############################

locals {
  # Team -> Linux-Gruppenname. Gruppen muessen mit einem Buchstaben beginnen,
  # daher das Praefix fuer Teams, die mit einer Ziffer anfangen.
  group_names = {
    for team in keys(var.users) : team => (
      can(regex("^[a-z]", trim(replace(lower(team), "/[^a-z0-9_-]+/", "-"), "-")))
      ? trim(replace(lower(team), "/[^a-z0-9_-]+/", "-"), "-")
      : "t-${trim(replace(lower(team), "/[^a-z0-9_-]+/", "-"), "-")}"
    )
  }

  all_emails = distinct(flatten([
    for team, members in var.users : [for member in members : member.email]
  ]))

  # E-Mail -> Linux-Benutzername.
  #
  # Trennzeichen im Lokalteil werden zu "-", nicht geloescht: wuerde man sie
  # ersatzlos entfernen, landeten "max.mustermann@dhbw.de" und
  # "maxmustermann@dhbw.de" im selben Account. Zwei Studierende teilten sich
  # dann eine Sitzung, und das zweite chpasswd ueberschriebe das erste
  # Passwort - der Output wiese einen Zugang aus, der nicht funktioniert.
  username_stems = {
    for email in local.all_emails :
    email => trim(replace(lower(split("@", email)[0]), "/[^a-z0-9]+/", "-"), "-")
  }

  usernames_by_email = {
    for email, stem in local.username_stems :
    email => can(regex("^[a-z]", stem)) ? stem : "u-${stem}"
  }

  all_users = flatten([
    for team, members in var.users : [
      for member in members : {
        id       = "${team}-${replace(split("@", member.email)[0], ".", "-")}"
        team     = team
        email    = member.email
        username = local.usernames_by_email[member.email]

        # Linux-Gruppenname. "Team #1" ist als Gruppe unzulaessig (Grossbuchstabe,
        # Leerzeichen, '#'), deshalb auf [a-z0-9_-] herunterbrechen: "team-1".
        # Der huebsche Name bleibt in team/metadata/outputs erhalten.
        group = local.group_names[team]
      }
    ]
  ])

  unique_teams  = distinct([for user in local.all_users : user.team])
  unique_groups = distinct([for user in local.all_users : user.group])

  usernames = [for user in local.all_users : user.username]
  emails    = [for user in local.all_users : user.email]
  user_ids  = [for user in local.all_users : user.id]
}

# Passwörter für jeden User generieren
resource "random_password" "user_passwords" {
  count            = length(local.all_users)
  length           = 16
  special          = true
  override_special = "!@%^*_-+="
  min_upper        = 1
  min_lower        = 1
  min_numeric      = 1
  min_special      = 1
}

# Packer-built image lookup by name (keine IDs hardcoden)
data "openstack_images_image_v2" "image" {
  name        = var.image_name
  most_recent = true
}

# -----------------------------------------------------------------------------
# Security Group für den RDP-Desktop
#
# Die gemeinsame Default-SG (var.shared_secgroup_id) laesst Port 3389 nicht
# durch und gehoert nicht dieser App. Deshalb legt die App ihre eigene an und
# haengt sie zusaetzlich an die Instanz. ethertype = "IPv6" ist entscheidend:
# eine IPv4-Regel waere hier wirkungslos, weil die VM nur ueber IPv6 erreichbar
# ist.
# -----------------------------------------------------------------------------
resource "openstack_networking_secgroup_v2" "rdp" {
  name        = "${local.app_name}-rdp"
  description = "RDP-Zugang (Port 3389) fuer den Kali-Desktop"
}

resource "openstack_networking_secgroup_rule_v2" "rdp_v6" {
  direction         = "ingress"
  ethertype         = "IPv6"
  protocol          = "tcp"
  port_range_min    = 3389
  port_range_max    = 3389
  remote_ip_prefix  = var.rdp_source_cidr
  security_group_id = openstack_networking_secgroup_v2.rdp.id
}

# -----------------------------------------------------------------------------
# Shared VM
# -----------------------------------------------------------------------------
resource "openstack_compute_instance_v2" "shared_vm" {
  name        = "${local.app_name}-shared"
  image_id    = data.openstack_images_image_v2.image.id
  flavor_name = var.flavor
  key_pair    = local.key_pair != "" ? local.key_pair : null

  # openstack_compute_instance_v2 erwartet Security-Group-NAMEN, nicht IDs -
  # deshalb hier .name der selbst angelegten Gruppe. Die geteilte SG kommt als
  # UUID/Name aus der Variable.
  security_groups = [var.shared_secgroup_id, openstack_networking_secgroup_v2.rdp.name]

  timeouts {
    create = "15m"
    delete = "15m"
  }

  network {
    uuid = var.network_uuid
  }

  user_data = templatefile("${path.module}/cloud-init-multi-user.yml.tpl", {
    all_users     = local.all_users
    unique_teams  = local.unique_teams
    unique_groups = local.unique_groups
    passwords     = [for p in random_password.user_passwords : p.result]
  })

  metadata = merge(local.metadata, {
    teams  = join(",", local.unique_teams)
    users  = join(",", local.usernames)
    emails = join(",", local.emails)
  })

  lifecycle {
    # Schon beim plan abbrechen, nicht erst wenn cloud-init still einen
    # Account ueberschreibt. Tritt auf, wenn dieselbe Person in zwei Teams
    # steht oder zwei Adressen auf denselben Namen abbilden.
    precondition {
      condition     = length(local.usernames) == length(distinct(local.usernames))
      error_message = "Roster ergibt doppelte Linux-Benutzernamen: ${join(", ", local.usernames)}. Jede Person darf nur einmal vorkommen."
    }
  }
}

# Warten bis cloud-init die Benutzer angelegt UND den Desktop gestartet hat.
# Fuer reines SSH reichten 90s; XRDP-Sitzungen sind aber erst spaeter bedienbar.
# Ohne das Warten meldet Terraform fertig, sobald die Instanz ACTIVE ist - die
# Zugangsdaten gehen dann raus, bevor der Remotedesktop erreichbar ist.
resource "time_sleep" "wait_for_vm" {
  depends_on      = [openstack_compute_instance_v2.shared_vm]
  create_duration = "180s"
}
