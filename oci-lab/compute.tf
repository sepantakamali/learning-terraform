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
