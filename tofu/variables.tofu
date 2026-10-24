################################################
# PFLICHT-Variablen
################################################

variable "users" {
  description = "Per-team roster — vom Worker injiziert."
  type = map(list(object({
    email = string
  })))
  default = {}
}

################################################
# Konfigurierbare Variablen
################################################

# Basis ist Debian, nicht Kali: in OpenStack liegt kein Kali-Image, und Images
# koennen nur die Cloud-Admins hinzufuegen. scripts/01-base.sh stellt die VM
# beim ersten Start auf kali-rolling um (getestet ab Debian 12 und 13).
variable "source_image_name" {
  description = "Debian-Basis-Image, das beim ersten Start zu Kali umgestellt wird @openstack:image:name"
  type        = string
  default     = "Debian 13"
}

# gp1 hat nur 10 GB Platte (~9 GB frei) - zu wenig: die Einrichtung verlangt
# mindestens 15 GB (Platzcheck in scripts/01-base.sh). win11.medium (2 vCPU,
# 8 GB RAM, 80 GB) bootet ohne Cinder-Volume und reicht auch fuer mehrere
# gleichzeitige XFCE-Sitzungen mit Burp oder Metasploit. Der Name ist
# irrefuehrend, der Flavor ist nicht an Windows gebunden.
variable "flavor" {
  description = "Flavor der Kali-VM (mind. 20 GB Platte) @openstack:flavor:name"
  type        = string
  default     = "win11.medium"
}

#   ipv4  eine Schnittstelle im IPv4-Netz (network_v4_uuid)
#   ipv6  eine Schnittstelle im IPv6-Netz (network_uuid) - Standard
#   dual  IPv6-Netz als Hauptschnittstelle, dazu eine zweite im IPv4-Netz
variable "ip_mode" {
  description = "Adressfamilie: ipv4, ipv6 oder dual (beide)"
  type        = string
  default     = "ipv6"

  validation {
    condition     = contains(["ipv4", "ipv6", "dual"], var.ip_mode)
    error_message = "ip_mode muss \"ipv4\", \"ipv6\" oder \"dual\" sein."
  }
}

# Der Name bleibt network_uuid, damit bestehende Deployments beim Redeploy
# ihre gespeicherte Netzwahl weiter treffen.
variable "network_uuid" {
  description = "Netz mit öffentlicher IPv6, z. B. DHBWV6 - für ipv6 und dual @openstack:network:id"
  type        = string
  default     = "9b579624-d844-4df3-b38d-89978b31d37d"
}

variable "network_v4_uuid" {
  description = "Netz mit öffentlich gerouteter IPv4, z. B. DHBWv4 - für ipv4 und dual @openstack:network:id"
  type        = string
  default     = ""
}

variable "shared_secgroup_id" {
  description = "ID der gemeinsamen Security Group für alle VMs @openstack:security_group:id"
  type        = string
  default     = "7ca4f889-e11e-4a16-83a8-73a77ebdbbe6"
}

variable "rdp_source_cidr" {
  description = "IPv6-Präfix, das auf Port 3389 (RDP) zugreifen darf. Sollte auf das DHBW-Campuspräfix eingegrenzt werden — ein weltweit offener RDP-Port auf einer Kali-VM ist ein lohnendes Ziel."
  type        = string
  default     = "::/0"
}

# Ueber IPv4 ist das Campusnetz bekannt, also gleich darauf begrenzt.
variable "rdp_source_cidr_v4" {
  description = "IPv4-Präfix, das auf Port 3389 (RDP) zugreifen darf - nur bei ip_mode ipv4 und dual"
  type        = string
  default     = "141.72.0.0/16"
}
