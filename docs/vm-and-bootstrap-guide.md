# VM, networking, and bootstrap reference

This chapter documents the VM implementation, its network dependencies, and the commands for setup and troubleshooting.

## What a VM is

A virtual machine (VM) is a virtual computer with allocated CPU, memory, network interfaces, and disks, running its own operating-system kernel. The cloud provider operates the physical hardware and virtualization layer. You manage the guest OS and applications.

Our VM runs Ubuntu. Docker runs on Ubuntu, and the Nginx container runs through Docker. Containers share the host Linux kernel. Nginx serves our HTML page; Docker supplies container execution and isolation.

```text
OCI physical infrastructure
└── VM: learning-application-vm
    ├── Boot volume — persistent storage 
    │   ├── Ubuntu system files and installed Docker software — contains all disk storage used by this VM; no additional block volumes are attached.
    │   ├── Docker image and container data
    │   └── Website content: /opt/learning-app/index.html
    ├── Primary VNIC — connection to the application subnet
    │   └── Private IP with an associated public IP
    └── Ubuntu — running guest operating system
        ├── SSH service — VM port 22
        └── Docker service — manages containers
            └── Container: learning-web
                ├── Image: nginx:stable-alpine
                ├── Nginx web server — serves HTML over HTTP
                ├── Published port: VM TCP 80 → container TCP 80
                └── Content directory: /usr/share/nginx/html
                    └── Read-only bind mount from VM: /opt/learning-app
```

## VM concepts in the configuration

| Setting | Meaning in this lab |
|---|---|
| Compartment | OCI resource organization and IAM scope; not a VM or network |
| Availability domain (AD) | One or more isolated data centres within the region; the VM placement location |
| Shape | Virtual hardware allocation; E2.1.Micro is the selected fixed shape |
| Image | OS boot template; the chosen Ubuntu image must support x86 and the shape |
| Boot volume | Persistent virtual disk used for the OS and local files; configured as 50 GiB |
| VNIC | Virtual Network Interface Card: adapter attached to the VM and connected to a subnet; Ubuntu uses it through a network driver |
| Private IP | Address allocated from the subnet to the VNIC |
| Public IP | Internet-facing address associated with a private IP on the VNIC; routing and security rules are also required |
| Metadata | Includes the SSH public key and cloud-init user data |
| Tags | Classification labels; used for clarification and labeling |

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

| Component | Role in our network |
|---|---|
| VCN (Virtual Cloud Network) | Private network with the address range `10.0.0.0/16` |
| Subnet | A section of the VCN using `10.0.1.0/24`; multiple VNICs can connect with distinct private IPs |
| Internet gateway | Shared internet connection for the VCN; performs public/private IPv4 translation for instances using public IPs |
| Route table | Separate OCI resource associated with our subnet; selects the next destination for traffic |
| Security list | Associated with the subnet; permits or blocks traffic according to protocol, addresses, and ports |

We create the VCN first. The gateway, route table, and security list reference it; the route table also references the gateway. The subnet references the VCN, route table, and security list. During VM creation, `create_vnic_details` selects that subnet, creates the primary VNIC, and requests a public IP. OCI allocates a private IP from the subnet and associates the public IP with it. Independent resources can be created in parallel.

The VNIC and internet gateway provide virtual networking-device functions implemented by OCI. Ubuntu sees the VNIC as an interface such as `ens3`. Ubuntu's networking software manages TCP connections and delivers traffic to applications using ports.

In our route rule, `destination = "0.0.0.0/0"` matches all IPv4 destinations, while `network_entity_id` separately selects the internet gateway. More-specific routes take precedence, including local VCN routing. This rule chooses a path; it does not grant permission or assign an IP to the gateway. Our route table is associated with the subnet, not configured inside the gateway.

For incoming internet traffic, the gateway translates the public destination IP to its associated private IP. The VNIC delivers the traffic to Ubuntu. These are simplified paths; security rules must also permit the traffic:

```text
SSH client → public IP:22 → internet gateway / address translation
           → VNIC → Ubuntu SSH service

Browser → public IP:80 → internet gateway / address translation
        → VNIC → Ubuntu / Docker port mapping → container port 80 → Nginx
```

HTTP ingress permits TCP 80 from any IPv4 source; SSH permits TCP 22 only from `ssh_source_cidr`. `stateless = false` makes the rules stateful: matching return traffic is allowed without a separate return rule. This tracks traffic for filtering; Ubuntu's TCP implementation manages the connection. Host firewall rules can also affect reachability.

See Oracle's [networking FAQ](https://www.oracle.com/cloud/networking/virtual-cloud-network/faq/) for address translation and [internet gateway documentation](https://docs.oracle.com/en-us/iaas/Content/Network/Tasks/managingIGs.htm) for routing.

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

File: [cloud-init.yaml](../oci-lab/cloud-init.yaml). `.yaml` and `.yml` are equivalent YAML filename extensions. The cloud-init file uses .yaml, while GitHub Actions workflow files use .yml. Both extensions represent YAML. File references must match the actual filename.

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

`#cloud-config` identifies the user data as cloud-init configuration written in YAML. Package setup (package_update) refreshes package metadata and installs Docker; `write_files` creates the HTML file; `runcmd` supplies commands executed in the final stage. Terraform sends the entire configuration as user data, and cloud-init inside Ubuntu processes it. Our bootstrap is intended for initial instance setup. An ordinary reboot does not repeat this.

Terraform detects edits to this file because `file("${path.module}/cloud-init.yaml")` reads its contents and `base64encode(var.cloud_init)` supplies them as `metadata.user_data`. In the OCI provider version locked for `oci-lab` (9.2.0), `ForceNewIfChange("metadata", ...)` compares the old and new `user_data` values and requires instance replacement if they differ. See the [provider's replacement rule](https://github.com/oracle/terraform-provider-oci/blob/v9.2.0/internal/service/core/core_instance_resource.go#L1025).

Therefore, after editing the YAML, `terraform plan` proposes replacing `module.web_server.oci_core_instance.web`: destroying the old VM and creating a new one. With no other changes, the summary is `1 to add, 0 to change, 1 to destroy`.

Nginx is already installed as part of the docker image. Docker downloads that image if it is not available locally and creates a container from it. Adding `nginx` to `packages:` would instead install a separate Nginx service directly on Ubuntu, which could conflict with Docker's published port if both try to use the VM's port 80.

`/opt/learning-app` is a directory on the Ubuntu VM, created by cloud-init for our website files. `learning-web` is the container. `/usr/share/nginx/html` is a directory (where the static files are stored) inside that container. The bind mount exposes the VM directory there without copying the files. Nginx reads `index.html` and sends it to the browser, which renders the HTML. `:ro` prevents changes through the container mount; the files can still be edited on the VM.

The Docker command, split across lines for explanation:

```bash
sudo docker run -d \
  --name learning-web \
  --restart unless-stopped \
  -p 80:80 \
  -v /opt/learning-app:/usr/share/nginx/html:ro \
  nginx:stable-alpine
```

This creates a container, do not run it again if `learning-web` already exists. Inspect or start the existing container instead.

| Part | Meaning |
|---|---|
| `-d` | Run detached from the terminal |
| `--name learning-web` | Assign a container name |
| `--restart unless-stopped` | Restart according to this policy, respecting explicit stops |
| `-p 80:80` | Publish host port 80 to container port 80 |
| `-v host:container:ro` | Bind the host directory into the container read-only |
| `nginx:stable-alpine` | Image and tag |

`systemctl enable --now docker` enables Docker on future boots and starts it immediately.

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

On the SSH client, from `oci-lab`:

```bash
VM_IP=$(terraform output -raw application_public_ip)
ssh -i ~/.ssh/oci_learning -o IdentitiesOnly=yes "ubuntu@$VM_IP"
```

`-raw` returns the IP without Terraform's display quotes, and `$(...)` stores the command's output in `VM_IP`. SSH uses `-i` to select the private key. `-o` sets an SSH option; `IdentitiesOnly=yes` limits authentication to configured identities instead of trying every key offered by an SSH agent. `ubuntu` is the login user for this Ubuntu image.

On the VM, check the login user and CPU architecture:

```bash
whoami
uname -m
```

The expected results are `ubuntu` and `x86_64`.

Check memory and disk space:

```bash
free -h
df -h /
```

`-h` displays sizes in readable units. `df -h /` shows disk usage for the filesystem containing `/`; `free -h` shows memory usage. In the memory output:

- `free` is RAM currently unused.
- `buff/cache` includes RAM used for buffers and caches, some of which can be reclaimed.
- `available` estimates how much RAM new work can use without swapping. This can be much larger than `free` because Linux can reclaim cache.
- `Mi` means mebibytes: one MiB is 1,048,576 bytes.

In the lab, `78Mi` free and `522Mi` available did not mean only 78 MiB remained usable. The available figure included memory Linux could reclaim.

Check that bootstrap has finished and the web service is running:

```bash
sudo cloud-init status --wait
sudo systemctl status docker --no-pager
sudo docker ps
curl -i http://localhost
```

`--wait` waits for cloud-init to finish. `--no-pager` prints Docker's service status directly without opening a scrollable viewer. `docker ps` lists running containers. `curl -i` includes HTTP response headers; here, `localhost` tests the web service from inside the VM. Expect cloud-init status `done`, the running `learning-web` container, and HTTP 200 with the project's HTML.

Leave the SSH session with `exit`, then test from the client:

```bash
curl -i "http://$VM_IP"
```

This request uses the public network path. If the request inside the VM works but this one fails, check public addressing, routing, and firewall rules.

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

On the SSH client, diagnose SSH connection establishment:

```bash
ssh -v -o ConnectTimeout=10 -i ~/.ssh/oci_learning \
  -o IdentitiesOnly=yes "ubuntu@$VM_IP"
```

A timeout suggests reachability/filtering; `Permission denied (publickey)` suggests username/key authorization. Host-key mismatch is another distinct issue. Verify unexpected identity changes rather than automatically deleting the host record.

SSH stores previously accepted server keys in the client's `~/.ssh/known_hosts`. One server can have entries for several key algorithms. After an intentional VM replacement, remove an obsolete host entry using the old IP:

```bash
ssh-keygen -R OLD_VM_IP
```

Replace `OLD_VM_IP` with the actual old address. This removes the saved server identity, not the private login key. For an unexpected host-key change, verify the server's identity before accepting a new key.

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

Retrieve the new IP through outputs, reconnect, and verify cloud-init/Docker/HTTP again. For obsolete SSH host records, follow the procedure in [Troubleshooting commands](#troubleshooting-commands).

## What Terraform can and cannot verify here

A no-change Terraform plan confirms no detected drift for managed infrastructure attributes. It does not prove the guest is healthy or that the web page works. Cloud-init logs, service status, container status, and HTTP requests verify those layers. Manual edits inside the VM are not automatically represented in Terraform state. The lab uses HTTP, a single VM, and host-local content; additional production requirements would need deliberate design.
