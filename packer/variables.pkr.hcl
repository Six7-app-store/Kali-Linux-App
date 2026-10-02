# Basis ist das vorhandene Debian-Image, kein Kali-Image.
#
# In OpenStack liegt kein Kali-Image, und Images koennen nur die Cloud-Admins
# hinzufuegen - der App Store selbst laedt keine hoch. 01-base.sh stellt Debian
# waehrend des Builds komplett auf kali-rolling um (getestet ab Debian 12 und 13).
variable "source_image_name" {
  type        = string
  description = "Debian-Basis-Image, das beim Build zu Kali umgestellt wird @openstack:image:name"
  default     = "Debian 13"
}

variable "image_name" {
  type        = string
  description = "Glance-Image-Name — vom Worker zur Build-Zeit gesetzt. @platform:internal"
  default     = "kali-v1"
}

variable "networks" {
  type        = list(string)
  description = "@openstack:network:id:list Build-Netzwerke"
  default     = ["9b579624-d844-4df3-b38d-89978b31d37d"]
}

variable "security_groups" {
  type        = list(string)
  description = "@openstack:security_group:id:list Build-Security-Groups"
  default     = ["7ca4f889-e11e-4a16-83a8-73a77ebdbbe6"]
}
