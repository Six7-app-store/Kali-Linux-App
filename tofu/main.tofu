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
# Erreichbar ist die Instanz ueber die feste Adresse der gewaehlten Familie
# (var.ip_mode). Die IPv4 im DHBWV6-Netz ist eine private NAT-Adresse
# (10.200.x.x) und taugt nicht als Verbindungsziel.

############################
# ADRESSFAMILIEN (var.ip_mode)
############################

locals {
  ethertypes = {
    ipv4 = ["IPv4"]
    ipv6 = ["IPv6"]
    dual = ["IPv4", "IPv6"]
  }[var.ip_mode]

  # Bei dual liegt die Hauptschnittstelle im IPv6-Netz: dessen private IPv4
  # bringt den Weg nach draussen (Kali-Paketquellen) ueber NAT mit, die
  # oeffentliche IPv4 kommt als zweite Schnittstelle dazu.
  primary_network_id = var.ip_mode == "ipv4" ? var.network_v4_uuid : var.network_uuid

  dual = var.ip_mode == "dual"
}

# Zweite Schnittstelle fuer dual, vorab als Port angelegt: so sind MAC und
# Adresse schon bekannt, wenn cloud-init sein user-data bekommt.
resource "openstack_networking_port_v2" "v4" {
  count      = local.dual ? 1 : 0
  name       = "${local.app_name}-shared-v4"
  network_id = var.network_v4_uuid

  security_group_ids = [
    var.shared_secgroup_id,
    openstack_networking_secgroup_v2.rdp.id,
  ]
}

# Praefix und Gateway des IPv4-Netzes fuer die eigene Routing-Tabelle der
# zweiten Schnittstelle (scripts/08-ipv4.sh).
data "openstack_networking_subnet_v2" "v4" {
  count      = local.dual ? 1 : 0
  network_id = var.network_v4_uuid
  ip_version = 4

  lifecycle {
    postcondition {
      condition     = self.gateway_ip != ""
      error_message = "Das IPv4-Netz in network_v4_uuid hat kein Gateway; dual braucht eins fuer die Antworten der zweiten Schnittstelle."
    }
  }
}

locals {
  secondary_ipv4 = local.dual ? one([for ip in openstack_networking_port_v2.v4[0].all_fixed_ips : ip if !strcontains(ip, ":")]) : ""

  # Eine Zeile fuer 08-ipv4.sh: "<mac> <adresse>/<praefix> <netz> <gateway>".
  # Leer, wenn es keine zweite Schnittstelle gibt.
  secondary_config = local.dual ? join(" ", [
    openstack_networking_port_v2.v4[0].mac_address,
    "${local.secondary_ipv4}/${split("/", data.openstack_networking_subnet_v2.v4[0].cidr)[1]}",
    data.openstack_networking_subnet_v2.v4[0].cidr,
    data.openstack_networking_subnet_v2.v4[0].gateway_ip,
  ]) : ""
}

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

# Basis-Image per Name (keine IDs hardcoden). Kein Image-Build mehr: die VM
# startet als Debian und stellt sich beim ersten Start selbst auf Kali um.
data "openstack_images_image_v2" "image" {
  name        = var.source_image_name
  most_recent = true
}

locals {
  # Alle Skripte aus scripts/ gehen in die user_data, gzip+base64 wegen des
  # 64-KB-Limits. Das ganze Verzeichnis statt einer Liste: setup.sh fuehrt
  # jedes NN-*.sh aus, ein neuer Schritt braucht also nur eine neue Datei.
  setup_scripts = {
    for name in fileset("${path.module}/scripts", "*.sh") :
    name => base64gzip(file("${path.module}/scripts/${name}"))
  }
}

# -----------------------------------------------------------------------------
# Security Group für den RDP-Desktop
#
# Die gemeinsame Default-SG (var.shared_secgroup_id) laesst Port 3389 nicht
# durch und gehoert nicht dieser App. Deshalb legt die App ihre eigene an und
# haengt sie zusaetzlich an die Instanz. Regeln je Adressfamilie aus
# var.ip_mode: eine IPv4-Regel laesst kein IPv6-Paket durch und umgekehrt.
# SSH steht mit drin, weil die gemeinsame Gruppe es nicht fuer jede Familie
# zusichert.
#
# Der Name braucht einen Zufallsanhang. Nova loest die Gruppen einer Instanz
# ueber den Namen auf, auch wenn unten die ID steht. Gibt es den Namen
# zweimal im Projekt (zweites Deployment, liegengebliebene Gruppe), scheitert
# jeder Bauversuch mit "Multiple security groups found matching", und die VM
# endet in ERROR (Staging, 24.10.2026).
# -----------------------------------------------------------------------------
resource "random_string" "secgroup_suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "openstack_networking_secgroup_v2" "rdp" {
  name        = "${local.app_name}-rdp-${random_string.secgroup_suffix.result}"
  description = "RDP-Zugang (Port 3389) fuer den Kali-Desktop, dazu SSH"
}

resource "openstack_networking_secgroup_rule_v2" "rdp" {
  for_each = toset(local.ethertypes)

  direction         = "ingress"
  ethertype         = each.key
  protocol          = "tcp"
  port_range_min    = 3389
  port_range_max    = 3389
  remote_ip_prefix  = each.key == "IPv4" ? var.rdp_source_cidr_v4 : var.rdp_source_cidr
  security_group_id = openstack_networking_secgroup_v2.rdp.id
  description       = "RDP (${each.key})"
}

resource "openstack_networking_secgroup_rule_v2" "ssh" {
  for_each = toset(local.ethertypes)

  direction         = "ingress"
  ethertype         = each.key
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = each.key == "IPv4" ? "0.0.0.0/0" : "::/0"
  security_group_id = openstack_networking_secgroup_v2.rdp.id
  description       = "SSH (${each.key})"
}

# -----------------------------------------------------------------------------
# Shared VM
# -----------------------------------------------------------------------------
resource "openstack_compute_instance_v2" "shared_vm" {
  name        = "${local.app_name}-shared"
  image_id    = data.openstack_images_image_v2.image.id
  flavor_name = var.flavor
  key_pair    = local.key_pair != "" ? local.key_pair : null

  # Per ID, nicht per Name: Nova nimmt beides an (die geteilte SG kommt
  # ohnehin als UUID). Ein Name ist aber nicht eindeutig - steht von einem
  # anderen oder unvollstaendig abgeraeumten Deployment noch eine zweite
  # "kali-user-rdp" im Projekt, lehnt Nova die VM ab und apply scheitert.
  # Gesehen am 14.10.2026 bei zwei Deploys von v2.0.1.
  security_groups = [var.shared_secgroup_id, openstack_networking_secgroup_v2.rdp.id]

  timeouts {
    create = "15m"
    delete = "15m"
  }

  # Nur die Hauptschnittstelle. Die zweite bei dual haengt interface_attach
  # unten an; eingerichtet wird sie von scripts/08-ipv4.sh.
  network {
    uuid = local.primary_network_id
  }

  user_data = templatefile("${path.module}/cloud-init-multi-user.yml.tpl", {
    all_users        = local.all_users
    unique_teams     = local.unique_teams
    unique_groups    = local.unique_groups
    passwords        = [for p in random_password.user_passwords : p.result]
    scripts          = local.setup_scripts
    secondary_config = local.secondary_config
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
    precondition {
      condition     = var.ip_mode == "ipv6" || var.network_v4_uuid != ""
      error_message = "ip_mode \"${var.ip_mode}\" braucht ein IPv4-Netz in network_v4_uuid."
    }
    precondition {
      condition     = var.ip_mode == "ipv4" || var.network_uuid != ""
      error_message = "ip_mode \"${var.ip_mode}\" braucht ein IPv6-Netz in network_uuid."
    }
  }

  depends_on = [openstack_networking_secgroup_rule_v2.rdp, openstack_networking_secgroup_rule_v2.ssh]
}

# Zweite Schnittstelle (dual) an die laufende Instanz.
resource "openstack_compute_interface_attach_v2" "v4" {
  count       = local.dual ? 1 : 0
  instance_id = openstack_compute_instance_v2.shared_vm.id
  port_id     = openstack_networking_port_v2.v4[0].id
}

# Kein Warten auf die fertige Einrichtung in apply: die Umstellung auf Kali mit
# Desktop und Werkzeugen beim ersten Start dauert laenger, als der worker apply
# laufen laesst (30 min). apply endet, sobald die VM laeuft; die Zugangsdaten
# funktionieren fuer SSH sofort, RDP erst nach der Einrichtung. Status zeigt
# /etc/motd beim Login, validate.sh prueft /var/lib/kali-app/ready.
