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

variable "description" {
  description = "Optional override for the compartment description."
  type        = string
  default     = null
}

variable "owner" {
  description = "Optional ownership tag for the compartment."
  type        = string
  default     = null

  validation {
    condition     = var.owner == null ? true : trimspace(var.owner) != ""
    error_message = "Owner must be null or a nonblank string."
  }
}

resource "oci_identity_compartment" "compartment" {
  compartment_id = var.parent_compartment_id
  name           = "learning-env-${var.environment}"
  description    = var.description != null ? var.description : "Terraform-managed ${var.environment} environment"
  enable_delete  = true

  freeform_tags = var.owner != null ? { owner : var.owner } : null
}

output "compartment_id" {
  value = oci_identity_compartment.compartment.id
}
