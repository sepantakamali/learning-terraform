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
