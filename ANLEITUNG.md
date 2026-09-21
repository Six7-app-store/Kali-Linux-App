# App-Vorlage für OpenStack — Aufbau und Anleitung (Kali-Desktop)

Diese Dateien beschreiben eine Kali-Linux-App mit grafischem Desktop für den
DHBW App Store. Sie sind auf `newstack.dhbw.cloud`, Projekt
`ma_wwi_24sea_appstore_g1` abgestimmt. Der Aufbau entspricht der Ubuntu-App;
der Unterschied ist die vollständige Desktop-Integration (XFCE über XRDP).

---

## 0. Vorbedingung: Kali-Basis-Image nach OpenStack

Anders als bei Ubuntu liegt auf newstack **kein** Kali-Basis-Image bereit. Es
muss einmalig hochgeladen werden, sonst bricht der Packer-Build sofort ab (wie
seinerzeit bei `Ubuntu 22.04`, siehe §5).

```bash
export OS_CLOUD=openstack   # Campusnetz oder VPN erforderlich

# Kali "Generic Cloud"-Image von cdimage.kali.org laden und entpacken, dann:
openstack image create "Kali Linux 2025.3" \
  --disk-format qcow2 --container-format bare \
  --file kali-linux-2025.3-cloud-genericcloud-amd64.qcow2 \
  --property hw_qemu_guest_agent=yes --private

openstack image list --private   # Namen exakt notieren
```

Der Name muss anschließend genauso in `packer/variables.pkr.hcl` unter
`source_image_name` stehen. Ob das Projekt Images anlegen darf und ob die Quota
reicht, ist vorab zu prüfen. Ebenfalls hier den passenden Flavor ermitteln:

```bash
openstack flavor list   # welcher Flavor ersetzt gp1.small? -> in locals.flavor
```

---

## 1. Was die Dateien tun

| Datei | Aufgabe |
|---|---|
| `packer/template.pkr.hcl` | Beschreibt, wie das Image gebaut wird: Basis-Image, Flavor, Netz |
| `packer/variables.pkr.hcl` | Die Stellschrauben des Builds |
| `packer/scripts/provision.sh` | **Was installiert wird** — Desktop, XRDP, Werkzeuge, Kursinhalt |
| `terraform/main.tf` | Erzeugt die VM aus dem gebauten Image, legt die RDP-Security-Group an |
| `terraform/variables.tf` | Netz, Security Group, RDP-Quelle, Nutzerliste |
| `terraform/cloud-init-multi-user.yml.tpl` | **Was beim ersten Start passiert** — Konten, Desktop-Dienst, Firewall |
| `terraform/outputs.tf` | Was der Studierende als Zugangsdaten zu sehen bekommt |

Die Kette dahinter:

```
Packer baut ein Image  →  Terraform erzeugt daraus eine VM
                       →  Terraform übergibt user_data
                       →  cloud-init richtet beim ersten Boot alles ein
```

**Terraform legt keine Nutzer an.** Es reicht nur einen Zettel (`user_data`) an
die VM weiter. Wer ihn abarbeitet, ist cloud-init *innerhalb* der VM.

---

## 2. Weg A: Über den App Store (der vorgesehene Weg)

So rollen die Studierenden die App später aus. Du brauchst dafür **keine**
dieser Dateien lokal — nur ein Git-Repo, auf das der App Store zeigt.

1. **OpenStack-Zugangsdaten hinterlegen** — im App Store unter
   *OpenStack-Credentials* die eigene `clouds.yaml` hochladen.
2. **App registrieren** — Git-URL und Release angeben, z. B.
   `https://github.com/Six7-app-store/Kali-Linux-App` mit Release `v1.0.0`.
3. **Freigeben** — über die Admin-Seite unter `/admin/apps`.
4. **Deployment starten** — der Assistent führt durch Konfiguration, Teams und
   Variablen.

Der Worker erledigt dann: Repo klonen → `packer build` → `terraform apply` →
Zugangsdaten je Studierendem ausgeben.

**Wichtig:** Das App-Repo hat bewusst keinen Deploy-Knopf. Die enthaltenen
GitHub-Workflows prüfen nur Formatierung und Syntax (`fmt`, `validate`,
`tflint`, `tfsec`) — sie fassen OpenStack nicht an und enthalten keine
Zugangsdaten.

---

## 3. Weg B: Von Hand, zum Ausprobieren

### Voraussetzungen

- `packer` und `terraform`
- Eine `clouds.yaml` unter `~/.config/openstack/clouds.yaml`
- Das Kali-Basis-Image aus §0 muss bereits hochgeladen sein
- Campusnetz oder VPN

```bash
export OS_CLOUD=openstack
```

### Schritt 1: Image bauen

```bash
cd packer
packer init .
packer build -var image_name=kali-app-v1 .
```

Dauert etwa 20–35 Minuten. Am Ende liegt ein neues Image `kali-app-v1` in
OpenStack. Prüfen mit `openstack image list --private`.

### Schritt 2: VM erzeugen

Lege eine Datei `terraform/meine.auto.tfvars` an:

```hcl
image_name = "kali-app-v1"

users = {
  "Team 1" = [
    { email = "vorname.nachname@dhbw.de" },
  ]
}
```

```bash
cd ../terraform
terraform init
terraform plan
terraform apply
```

### Schritt 3: Zugangsdaten auslesen

```bash
terraform output -json user_accounts
```

Darin stehen Benutzername, Passwort, IPv6-Adresse und Port 3389. Verbinden per
Remotedesktop (Windows `mstsc`, Ziel `[<ipv6>]:3389`) oder alternativ per SSH.

### Schritt 4: Wieder abräumen

```bash
terraform destroy
openstack image delete kali-app-v1
```

---

## 4. Eine eigene App daraus machen

Drei Stellen, mehr braucht es meistens nicht:

**`packer/scripts/provision.sh`** — was installiert wird: Desktop, XRDP-Setup,
Werkzeuge und der Kursinhalt unter `/etc/skel/`.

**`terraform/cloud-init-multi-user.yml.tpl`** — was beim ersten Start passiert:
Konten anlegen, Firewall öffnen, Desktop-Dienst starten.

**`terraform/outputs.tf`** — was der Studierende angezeigt bekommt. Der Block
`user_accounts` ist als `[CONTRACT]` markiert: Der App Store erwartet diese
Struktur, also die Felder beibehalten und nur die Werte anpassen (hier
`port = 3389`).

Dazu in `terraform/main.tf` unter `locals` die App-Vorgaben:

```hcl
app_name = "kali-user"    # Namenspräfix der VM
flavor   = "gp1.medium"   # Größe (Desktop braucht mehr als eine Terminal-VM)
```

---

## 5. Stolpersteine

**Basis-Image.** Auf newstack gibt es kein Kali-Image — es muss zuerst
hochgeladen werden (§0). `source_image_name` muss exakt auf den Upload-Namen
zeigen, sonst bricht der Build sofort ab.

**XRDP muss auf IPv6 lauschen.** Standardmäßig bindet xrdp auf `0.0.0.0` (nur
IPv4). Im DHBWV6-Netz ist IPv4 aber eine private NAT-Adresse; öffentlich ist
nur IPv6. `provision.sh` setzt deshalb `port=tcp6://:3389` und
`enable_ipv6=true`. Ohne das läuft der Dienst, ist aber von außen unerreichbar
— der teuerste Fehler, weil alles andere funktioniert.

**Port 3389 braucht eine eigene Security Group.** Die geteilte Default-SG lässt
RDP nicht durch. `main.tf` legt eine eigene SG mit einer **IPv6-Ingress-Regel**
(`ethertype = "IPv6"`) an — eine IPv4-Regel wäre hier wirkungslos.

**debconf blockiert den Build.** Die Wireshark-Installation fragt interaktiv
nach Capture-Rechten und lässt den Build hängen. `provision.sh` beantwortet die
Frage vorab per `debconf-set-selections` und setzt `DEBIAN_FRONTEND=noninteractive`.

**Fest verdrahtete UUIDs.** Netz und Security Group als Defaults:

| Ressource | UUID |
|---|---|
| Netz `DHBWV6` | `9b579624-d844-4df3-b38d-89978b31d37d` |
| Security Group `default` | `7ca4f889-e11e-4a16-83a8-73a77ebdbbe6` |

**IPv4 ist nicht erreichbar / Floating IPs helfen nicht.** Wie bei der
Ubuntu-App: die Outputs geben `fixed_ip_v6` aus, `enable_floating_ip = false`.

**Der Image-Name muss übereinstimmen.** Was bei `packer build` als
`image_name` gesetzt wird, muss in Terraform dasselbe sein.

**Build-Zeit.** Der App Store bricht einen Packer-Build nach **einer Stunde**
hart ab (`SIGKILL`). Der Kali-Desktop-Build liegt mit 20–35 Minuten darunter,
aber deutlich näher am Limit als die Terminal-App. Erste Stellschraube, falls
es eng wird: `kali-linux-headless` gegen eine kleinere, explizite Paketliste
tauschen.

**Verwaiste RDP-Sitzungen.** Getrennte, nicht abgemeldete Sitzungen laufen
weiter und belegen RAM der gemeinsamen VM. `provision.sh` und cloud-init setzen
deshalb Sitzungsgrenzen in `sesman.ini` (`DisconnectedTimeLimit`).
