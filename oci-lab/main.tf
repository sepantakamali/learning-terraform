terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~>9.2"
    }
  }
}

provider "oci" {
  config_file_profile = "LEARNING_TERRAFORM"
}

variable "tenancy_ocid" {
  description = "OCID of the OCI tenancy"
  type        = string
}

data "oci_identity_availability_domains" "available" {
  compartment_id = var.tenancy_ocid
}

output "availability_domains" {
  value = data.oci_identity_availability_domains.available.availability_domains
}

variable "ssh_source_cidr" {
  description = "Public IPv4 address allowed to connect through SSH, with /32"
  type        = string
}

variable "ssh_public_key_path" {
  description = "Path to the public SSH key installed on the ubuntu VM"
  type        = string
}

variable "ubuntu_image_id" {
  description = "OCID of the Ubuntu ARM image used for the learning VM"
  type        = string
}
