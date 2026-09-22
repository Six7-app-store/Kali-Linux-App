# Troubleshooting

## Packer-Build fehlgeschlagen

**„image_name not found"**  
→ Base-Image liegt nicht in OpenStack. Schritt 0 (Upload) wiederholen.

**„SSH timeout"**  
→ Build-Flavor zu klein oder Startup dauert länger.  
→ `template.pkr.hcl`: `ssh_timeout = "30m"` erhöhen.

**„Permission denied"**  
→ Credentials falsch. `export OS_CLOUD=openstack` prüfen.  
→ `openstack quota list` testen.

**provision.sh bricht ab**  
→ Logs in Packer-Output prüfen. Fehler in einem der Steps (01-05)?  
→ Lokal testen: `bash -n packer/scripts/0X-*.sh`

## Terraform apply fehlgeschlagen

**„missing required variable"**  
→ `image_name` in `meine.auto.tfvars` stimmt nicht mit Packer-Output überein.

**„Security group not found"**  
→ SG-UUID in `variables.tf` existiert nicht.  
→ `openstack security group list` prüfen.

**„template rendering failed"**  
→ YAML-Syntax in `cloud-init-multi-user.yml.tpl` kaputt.  
→ `terraform console` → manuell rendern + YAML-Parser testen.

## VM oben, aber nicht erreichbar

**SSH-Verbindung fehlgeschlagen**  
→ 180s Warten (cloud-init lädt). `validate.sh` gibt bessere Fehlermeldungen.

**XRDP nicht aktiv**  
```bash
ssh user@ipv6
sudo systemctl status xrdp
sudo journalctl -u xrdp -n 50
sudo systemctl restart xrdp
```

**Port 3389 nicht offen**  
```bash
sudo ufw status
sudo ufw allow 3389/tcp
sudo ufw --force enable
```

**Nutzer wurden nicht angelegt**  
```bash
sudo cat /var/log/setup-complete.log
sudo cat /var/log/cloud-init-output.log
```

## Idempotenz testen

```bash
terraform plan   # sollte "No changes" zeigen
terraform apply  # bestätigen
```

Sollte Änderungen zeigen → Fehler in HCL oder Terraform-State.

## post-Deployment-Checks

```bash
export SSH_PASS="<passwort>"
./validate.sh <user> <ipv6>
```

Gibt spezifische Fehler pro Service.
