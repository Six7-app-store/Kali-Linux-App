# Basis ist ein Debian-Cloud-Image aus dem Internet, kein Image aus Glance.
#
# In OpenStack liegt kein Kali-Image, und ueber den App Store laesst sich keins
# hochladen. Kalis eigene Cloud-Images gibt es nur als .tar.xz, das Glance nicht
# entpacken kann. Debian liefert eine direkt nutzbare qcow2; 01-base.sh stellt
# sie waehrend des Builds komplett auf kali-rolling um.
variable "source_image_url" {
  type        = string
  description = "URL des Debian-qcow2, das Glance per web-download laedt und das zu Kali umgebaut wird"
  default     = "https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2"
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
