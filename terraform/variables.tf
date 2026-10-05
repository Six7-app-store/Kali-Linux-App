################################################
# PFLICHT-Variablen
################################################

variable "users" {
  description = "Per-team roster — vom Worker injiziert. @platform:internal"
  type = map(list(object({
    email = string
  })))
  default = {}
}

variable "image_name" {
  description = "Glance-Image-Name des Kali-Images — vom Worker zur Apply-Zeit gesetzt. @platform:internal"
  type        = string
}

################################################
# Konfigurierbare Variablen
################################################

# Muss mindestens so viel Platte haben wie der Build-Flavor in
# packer/variables.pkr.hcl: das Image ist ein Snapshot von dessen Platte (nach
# growpart auf volle Groesse erweitert), ein kleinerer Flavor wird von Nova
# abgelehnt ("Flavor's disk is too small for requested image").
# gp1 hat nur 10 GB. win11.medium (2 vCPU, 8 GB RAM, 80 GB) reicht auch fuer
# mehrere gleichzeitige XFCE-Sitzungen mit Burp oder Metasploit.
variable "flavor" {
  description = "Flavor der Kali-VM (gleich gross wie der Packer-Build-Flavor) @openstack:flavor:name"
  type        = string
  default     = "win11.medium"
}

variable "network_uuid" {
  description = "Hauptnetzwerk @openstack:network:id"
  type        = string
  default     = "9b579624-d844-4df3-b38d-89978b31d37d"
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
