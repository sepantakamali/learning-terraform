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
