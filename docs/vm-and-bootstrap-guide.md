# VM, networking, and bootstrap reference

Checked against this repository on 23 October 2026. This chapter explains the actual VM implementation, not a separate deployment template. Source listings below need the existing root/module files and credentials; do not paste duplicate resource blocks into the project.

## What a VM is

A virtual machine (VM) is a virtual computer with allocated CPU, memory, network interfaces, and disks, running its own operating-system kernel. The cloud provider operates the physical hardware and virtualization layer. You manage the guest OS and applications.

Our VM runs Ubuntu. Docker runs on Ubuntu, and the Nginx container runs through Docker. Containers share the host Linux kernel; they are not additional full VMs. Nginx serves our HTML page; Docker supplies container execution and isolation, not HTTP application behavior.

```text
OCI physical infrastructure
└── virtual machine: learning-application-vm
    ├── Ubuntu operating system
    ├── boot volume: OS and /opt/learning-app/index.html
    ├── virtual network interface in application subnet
    └── Docker service
        └── learning-web container: Nginx
            └── /usr/share/nginx/html → host /opt/learning-app (read-only)
```

## VM concepts in the configuration

| Setting | Meaning in this lab |
|---|---|
| Compartment | OCI resource organization and IAM scope; not a VM or network |
| Availability domain | Placement location within the region |
| Shape | Virtual hardware allocation; E2.1.Micro is the selected fixed shape |
| Image | OS boot template; the chosen Ubuntu image must support x86 and the shape |
| Boot volume | Persistent virtual disk used for the OS and local files; configured as 50 GiB |
| VNIC | Virtual network interface attached to the subnet |
| Private IP | Address within the VCN, used for private routing |
| Public IP | Internet-facing address associated with the VNIC; alone it does not open ports |
| Metadata | Includes the SSH public key and cloud-init user data |
| Tags | Classification labels; they do not allocate hardware or grant access |

Earlier we explored A1.Flex, an Arm shape, and configurable CPU/memory. The final E2.1.Micro module does not contain a `shape_config` block. Do not copy flexible-shape memory settings into this fixed-shape definition. Capacity, compatibility, limits, and authorization are different failure categories. Our historical 404/shape errors did not prove a single cause for all failed attempts.

## Root module: connect the VM to existing resources

File: [compute.tf](../oci-lab/compute.tf). The moved blocks preserve the earlier address history; they do not create additional VMs. The availability-domain index is a lab-specific choice: inspect the returned domain name when adapting the configuration.

```hcl
moved {
  from = oci_core_instance.application
  to   = oci_core_instance.web
}

moved {
  from = oci_core_instance.web
  to   = module.web_server.oci_core_instance.web
}

module "web_server" {
  source = "./modules/web_server"

  compartment_id      = oci_identity_compartment.learning.id
  availability_domain = data.oci_identity_availability_domains.available.availability_domains[1].name
  subnet_id           = oci_core_subnet.application.id
  image_id            = var.ubuntu_image_id
  ssh_public_key      = file(pathexpand(var.ssh_public_key_path))
  cloud_init          = file("${path.module}/cloud-init.yaml")

  tags = {
    environment = "learning"
    managed_by  = "terraform"
  }
}

output "application_public_ip" {
  value = module.web_server.public_ip
}

output "application_private_ip" {
  value = module.web_server.private_ip
}
```

`file(pathexpand(...))` expands a path such as `~/.ssh/key.pub` and reads its public-key contents on the machine running Terraform. The private key stays with the SSH client. `path.module` identifies the directory containing this root module, making the cloud-init path independent of the shell's current directory.

References such as `oci_core_subnet.application.id` both supply values and establish Terraform dependencies. Do not manually copy a resource ID into a variable when this root already manages the resource and can reference it directly.

## Child module: create the instance

File: [modules/web_server/main.tf](../oci-lab/modules/web_server/main.tf).

```hcl
terraform {
  required_providers {
    oci = {
      source = "oracle/oci"
    }
  }
}

resource "oci_core_instance" "web" {
  compartment_id      = var.compartment_id
  availability_domain = var.availability_domain
  display_name        = "learning-application-vm"
  shape               = "VM.Standard.E2.1.Micro"

  source_details {
    source_type             = "image"
    source_id               = var.image_id
    boot_volume_size_in_gbs = 50
  }

  create_vnic_details {
    subnet_id        = var.subnet_id
    assign_public_ip = true
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data           = base64encode(var.cloud_init)
  }

  freeform_tags = var.tags
}
```

`source_type = "image"` boots from the selected image. `assign_public_ip = true` requests public addressing; routing and ingress rules still determine reachability. `ssh_authorized_keys` authorizes a corresponding private key for login. `base64encode` encodes user data for the API; it is not encryption, so do not treat metadata as secret storage.

The instance is created through the OCI provider API. Terraform does not SSH into it to execute cloud-init. Cloud-init runs inside the guest and reads the supplied user data.

### Module input declarations

File: [variables.tf](../oci-lab/modules/web_server/variables.tf).

```hcl
variable "compartment_id" {
  description = "OCID of the compartment containing the VM"
  type        = string
}

variable "availability_domain" {
  description = "Availability domain where the VM will run"
  type        = string
}

variable "subnet_id" {
  description = "OCID of the subnet for the VM"
  type        = string
}

variable "image_id" {
  description = "OCID of the operating system image"
  type        = string
}

variable "ssh_public_key" {
  description = "Public SSH key authorised to access the VM"
  type        = string
}

variable "cloud_init" {
  description = "Cloud-init configuration as plain text"
  type        = string
}

variable "tags" {
  description = "Freeform tags attached to the VM"
  type        = map(string)
  default     = {}

  validation {
    condition = contains(
      ["learning", "development", "production"],
      lookup(var.tags, "environment", "learning")
    )

    error_message = "The environment tag must be learning, development, or production."
  }
}
```

These inputs form the child module's interface. The root's module block supplies them. A root variable and a child variable are separate declarations even if they have the same name.

### Module outputs

File: [outputs.tf](../oci-lab/modules/web_server/outputs.tf).

```hcl
output "public_ip" {
  value = oci_core_instance.web.public_ip
}

output "private_ip" {
  value = oci_core_instance.web.private_ip
}
```

The child exports its IPs. The root republishes them as `application_public_ip` and `application_private_ip`, which are available through `terraform output`.

## Network path and exact configuration

```text
Mac → VM public IP:22 → OCI ingress rule → subnet/VNIC → Ubuntu SSH server
Browser → VM public IP:80 → OCI ingress rule → host port 80 → container port 80 → Nginx
```

The subnet references its route table and security list. The default route points at an internet gateway. HTTP ingress permits TCP 80 from everywhere for this lab; SSH permits TCP 22 only from `ssh_source_cidr`. Stateless is false, so these rules are stateful. Host-level firewall policy can also affect traffic.

File: [network.tf](../oci-lab/network.tf). This also declares the parent learning compartment and root networking outputs.

```hcl
resource "oci_identity_compartment" "learning" {
  compartment_id = var.tenancy_ocid
  name           = "learning-terraform-compartment"
  description    = "Resources for learning Terraform"
  enable_delete  = true
}

resource "oci_core_vcn" "learning" {
  compartment_id = oci_identity_compartment.learning.id
  display_name   = "learning-terraform-vcn"
  cidr_blocks    = ["10.0.0.0/16"]
}

resource "oci_core_internet_gateway" "learning" {
  compartment_id = oci_identity_compartment.learning.id
  vcn_id         = oci_core_vcn.learning.id
  display_name   = "learning-internet-gateway"
  enabled        = true
}

resource "oci_core_route_table" "public" {
  compartment_id = oci_identity_compartment.learning.id
  vcn_id         = oci_core_vcn.learning.id
  display_name   = "learning-public-routes"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.learning.id
  }
}

output "oci_lab_compartment_id" {
  value = oci_identity_compartment.learning.id
}

output "oci_lab_vcn_id" {
  value = oci_core_vcn.learning.id
}

resource "oci_core_subnet" "application" {
  compartment_id = oci_identity_compartment.learning.id
  vcn_id         = oci_core_vcn.learning.id
  display_name   = "learning-application-subnet"
  cidr_block     = "10.0.1.0/24"

  prohibit_public_ip_on_vnic = false

  route_table_id    = oci_core_route_table.public.id
  security_list_ids = [oci_core_security_list.application.id]
}

output "application_subnet_id" {
  value = oci_core_subnet.application.id
}

resource "oci_core_security_list" "application" {
  compartment_id = oci_identity_compartment.learning.id
  vcn_id         = oci_core_vcn.learning.id
  display_name   = "learning-application-security"

  ingress_security_rules {
    description = "Allow SSH from my public IP"
    protocol    = "6"
    source      = var.ssh_source_cidr
    source_type = "CIDR_BLOCK"
    stateless   = false

    tcp_options {
      min = 22
      max = 22
    }
  }

  ingress_security_rules {
    description = "Allow public HTTP"
    protocol    = "6"
    source      = "0.0.0.0/0"
    source_type = "CIDR_BLOCK"
    stateless   = false

    tcp_options {
      min = 80
      max = 80
    }
  }

  egress_security_rules {
    description      = "Allow outbound traffic"
    protocol         = "all"
    destination      = "0.0.0.0/0"
    destination_type = "CIDR_BLOCK"
    stateless        = false
  }
}
```

Changing your allowed source IP updates an OCI security-list rule. It does not change the VM's address, copy a CLI session, or install a new SSH key. `/32` denotes exactly one IPv4 address. Public addresses can change with ISP/network/VPN changes; restarting the Mac does not imply they always change.

## Bootstrap: install Docker and start Nginx

File: [cloud-init.yaml](../oci-lab/cloud-init.yaml).

```yaml
#cloud-config

package_update: true

packages:
  - docker.io

write_files:
  - path: /opt/learning-app/index.html
    permissions: '0644'
    content: |
      <!doctype html>
      <html lang="en">
        <head>
          <meta charset="utf-8">
          <title>Learning Terraform</title>
        </head>
        <body>
          <h1>My Terraform learning project</h1>
          <p>Ubuntu, Docker, and Nginx configured with cloud-init.</p>
        </body>
      </html>

runcmd:
  - systemctl enable --now docker
  - docker run -d --name learning-web --restart unless-stopped -p 80:80 -v /opt/learning-app:/usr/share/nginx/html:ro nginx:stable-alpine
```

`#cloud-config` identifies the user-data format. Package setup refreshes package metadata and installs Docker; `write_files` creates the HTML file; `runcmd` arranges commands run in the final stage. This bootstrap is intended for initial instance setup, not arbitrary repeated application deployments. Changing the local YAML does not by itself rerun it on an existing VM. [Cloud-init module reference](https://docs.cloud-init.io/en/latest/reference/modules.html)

`/opt` conventionally holds additional application software/data. `/opt/learning-app` is our chosen host directory, not a special Docker object. `/usr/share/nginx/html` is the web-content path inside this container. The mount connects them; one is not the parent directory of the other.

The Docker command, split across lines for explanation:

```bash
sudo docker run -d \
  --name learning-web \
  --restart unless-stopped \
  -p 80:80 \
  -v /opt/learning-app:/usr/share/nginx/html:ro \
  nginx:stable-alpine
```

This creates a container: do not run it again if `learning-web` already exists. Inspect or start the existing container instead.

| Part | Meaning |
|---|---|
| `-d` | Run detached from the terminal |
| `--name learning-web` | Assign a container name |
| `--restart unless-stopped` | Restart according to this policy, respecting explicit stops |
| `-p 80:80` | Publish host port 80 to container port 80 |
| `-v host:container:ro` | Bind the host directory into the container read-only |
| `nginx:stable-alpine` | Image and tag; the tag can change over time, unlike a pinned digest |

`systemctl enable --now docker` enables Docker on future boots and starts it immediately. In cloud-init these commands run with root privileges; interactive commands here use sudo. [Docker run reference](https://docs.docker.com/engine/containers/run/)

## Create or update deliberately

Run from `oci-lab`, with the backend and private input values already configured:

```bash
terraform init
terraform validate
terraform plan -out=vm-change.tfplan
terraform show vm-change.tfplan
# Execute only after reviewing every action in the plan:
terraform apply vm-change.tfplan
terraform output application_public_ip
terraform output application_private_ip
```

This plans the whole root, not only the VM. `-target` is not a routine way to ignore other changes. Creation finishing does not guarantee cloud-init or the web service is ready.

## Connect and verify

On the Mac, from `oci-lab`:

```bash
VM_IP=$(terraform output -raw application_public_ip)
ssh -i ~/.ssh/oci_learning -o IdentitiesOnly=yes "ubuntu@$VM_IP"
```

`-raw` returns a string without Terraform's display quotes. `$(...)` captures command output. SSH `-i` selects the private key; `-o` sets an SSH configuration option. `ubuntu` is this image's login user, not a universal cloud username.

On the VM:

```bash
whoami
uname -m
free -h
df -h /
sudo cloud-init status --wait
sudo systemctl status docker --no-pager
sudo docker ps
curl -i http://localhost
```

Expected: Ubuntu user, x86_64 architecture, cloud-init done, running `learning-web`, and HTTP 200 with our HTML. `curl -i` includes HTTP response headers; it is unrelated to SSH's `-i`. Exit SSH with `exit`.

Then on the Mac:

```bash
curl -i "http://$VM_IP"
```

A successful local curl plus failed external curl suggests investigating networking/public addressing/host filtering rather than assuming the HTML or Nginx is broken.

## Troubleshooting commands

On the VM:

```bash
sudo cloud-init status --long
sudo tail -n 100 /var/log/cloud-init-output.log
sudo tail -n 100 /var/log/cloud-init.log
sudo journalctl -u docker -n 100 --no-pager
sudo docker ps -a
sudo docker logs --tail 100 learning-web
sudo docker inspect learning-web
sudo docker exec learning-web nginx -t
sudo ss -lntp
ls -l /opt/learning-app/index.html
```

`docker ps -a` includes stopped containers; `logs` reads container output; `inspect` shows configuration; `nginx -t` checks Nginx configuration. `ss -lntp` displays listening TCP sockets and processes, but Docker forwarding need not always appear as a normal user-process listener. Inspect port mappings and connectivity as well. Logs and inspection output can contain operational details; review before sharing.

On the Mac, diagnose SSH connection establishment:

```bash
ssh -v -o ConnectTimeout=10 -i ~/.ssh/oci_learning \
  -o IdentitiesOnly=yes "ubuntu@$VM_IP"
```

A timeout suggests reachability/filtering; `Permission denied (publickey)` suggests username/key authorization. Host-key mismatch is another distinct issue. Verify unexpected identity changes rather than automatically deleting the host record.

## VM replacement exercise — destructive example, not routine maintenance

We intentionally rebuilt the lab VM to prove automatic bootstrap. This replaces the instance and can lose local boot-disk data and change public addressing. Preserve needed data and inspect the plan's disk consequences first.

Using the current resource address, from `oci-lab`:

```bash
terraform plan \
  -replace=module.web_server.oci_core_instance.web \
  -out=rebuild.tfplan
terraform show rebuild.tfplan
# Only for an intentionally approved rebuild:
terraform apply rebuild.tfplan
```

Retrieve the new IP through outputs, reconnect, and verify cloud-init/Docker/HTTP again. If a recorded host identity genuinely became obsolete, remove that known-host record with `ssh-keygen -R OLD_IP` after replacing the placeholder. This removes server-key records, not your private identity key. Multiple matching lines can be different server-key algorithms.

## What Terraform can and cannot verify here

A no-change Terraform plan confirms no detected drift for managed infrastructure attributes. It does not prove the guest is healthy or that the web page works. Cloud-init logs, service status, container status, and HTTP requests verify those layers. Manual edits inside the VM are not automatically represented in Terraform state. The lab uses HTTP, a single VM, and host-local content; additional production requirements would need deliberate design.
