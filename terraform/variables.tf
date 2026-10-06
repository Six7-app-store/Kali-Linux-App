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

# Ungenutzt. Der worker setzt image_name noch aus der Zeit mit gebautem
# Kali-Image. Ohne diese Deklaration bricht tofu apply mit "Value for
# undeclared variable" ab. Entfernen, sobald der worker sie nicht mehr setzt.
# tflint-ignore: terraform_unused_declarations
variable "image_name" {
  description = "Ungenutzt, nur fuer Kompatibilitaet mit dem worker. @platform:internal"
  type        = string
  default     = ""
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
