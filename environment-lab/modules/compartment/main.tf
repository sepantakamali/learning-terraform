terraform {
  required_providers {
    oci = {
      source = "oracle/oci"
    }
  }
}

variable "parent_compartment_id" {
  type = string
}

variable "environment" {
  type = string
}

resource "oci_identity_compartment" "compartment" {
  compartment_id = var.parent_compartment_id
  name = "learning-env-${var.environment}"
  description = "Terraform-managed ${var.environment} environment"
  enable_delete = true
}

output "compartment_id" {
  value = oci_identity_compartment.compartment.id
}
