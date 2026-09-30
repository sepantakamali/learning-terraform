resource "oci_core_instance" "application" {
  compartment_id      = oci_identity_compartment.learning.id
  availability_domain = data.oci_identity_availability_domains.available.availability_domains[1].name
  display_name        = "learning-application-vm"
  shape               = "VM.Standard.E2.1.Micro"

  source_details {
    source_type             = "image"
    source_id               = var.ubuntu_image_id
    boot_volume_size_in_gbs = 50
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.application.id
    assign_public_ip = true
  }

  metadata = {
    ssh_authorized_keys = file(pathexpand(var.ssh_public_key_path))
    user_data           = base64encode(file("${path.module}/cloud-init.yaml"))
  }
}

output "application_public_ip" {
  value = oci_core_instance.application.public_ip
}

output "application_private_ip" {
  value = oci_core_instance.application.private_ip
}
