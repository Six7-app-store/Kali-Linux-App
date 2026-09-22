# Kali-Linux-App – Anleitung

OpenStack App für DHBW App Store. Erzeugt eine Kali-VM mit XFCE-Desktop über XRDP.

## 0. Vorbedingung: Kali-Image hochladen

```bash
export OS_CLOUD=openstack  # Campusnetz oder VPN

# Image von cdimage.kali.org laden, dann:
openstack image create "Kali Linux 2025.3" \
  --disk-format qcow2 --container-format bare \
  --file kali-linux-2025.3-cloud-genericcloud-amd64.qcow2 \
  --property hw_qemu_guest_agent=yes --private
```

Image-Name muss in `packer/variables.pkr.hcl` stehen.

## 1. Dateistruktur

| Datei | Aufgabe |
|---|---|
| `packer/scripts/{01-05}.sh` | Build-Steps |
| `packer/scripts/provision.sh` | Orchestrator |
| `terraform/main.tf` | VM + Security Group |
| `terraform/cloud-init-multi-user.yml.tpl` | Erster Boot |
| `terraform/outputs.tf` | Zugangsdaten (Contract) |
| `validate.sh` | Post-Deployment-Test |

**Ablauf:** Packer baut Image → Terraform erzeugt VM → cloud-init konfiguriert Nutzer + Services.

## 2. Über App Store (Weg A)

1. Credentials hinterlegen (App Store)
2. Git-URL + Release registrieren
3. Admin-Freigabe
4. Deployment starten

## 3. Manuell (Weg B)

```bash
# Image bauen
cd packer
packer init .
packer build -var image_name=kali-app-v1 .

# VM erzeugen
cd ../terraform
cat > meine.auto.tfvars <<'EOF'
image_name = "kali-app-v1"
users = {
  "Team 1" = [
    { email = "vorname@dhbw.de" }
  ]
}
EOF

terraform init
terraform apply

# Zugangsdaten
terraform output -json user_accounts

# Validieren
export SSH_PASS="<passwort>"
../validate.sh <user> <ipv6>

# Aufräumen
terraform destroy
openstack image delete kali-app-v1
```

## 4. Anpassungen

**provision.sh:** Werkzeuge in `03-tools.sh` ändern.  
**cloud-init:** Services in `cloud-init-multi-user.yml.tpl` ändern.  
**Outputs:** Contract in `outputs.tf` behalten, nur Werte ändern.

## 5. Robustheit

- Alle Fehler werden sofort abgebrochen (trap-Handler)
- Post-Build-Verifikation in `05-verify.sh`
- Cloud-init prüft Services nach Startup
- `validate.sh` testet Deployment
- Fehlerbehandlung siehe `TROUBLESHOOTING.md`

## Bekannte Probleme

**Image nicht gefunden:** Schritt 0 wiederholen.  
**SSH-Timeout:** Flavor vergrößern oder `ssh_timeout` in `template.pkr.hcl` erhöhen.  
**XRDP nicht erreichbar:** IPv6-Binding prüfen (`port=tcp6://:3389`).  
**Firewall blockiert:** Cloud-init prüfen, `ufw status` auf VM.  
**Nutzer fehlgeschlagen:** Logs: `cat /var/log/setup-complete.log`.

Siehe auch: `TROUBLESHOOTING.md`
