variable "practice_compartments" {
  description = "Practice compartments and their lifecycle labels."

  type = map(object({
    description = string
    enabled     = bool
    purpose     = string
  }))

  default = {
    alpha = {
      description = "First practice compartment"
      enabled     = true
      purpose     = "temporary"
    }
    gamma = {
      description = "Second practice compartment"
      enabled     = true
      purpose     = "retained"
    }
  }

  validation {
    condition = alltrue([
      for settings in values(var.practice_compartments) :
      contains(["temporary", "retained"], settings.purpose)
    ])

    error_message = "Each compartment's purpose must be temporary or retained."
  }
}

moved {
  from = oci_identity_compartment.practice["beta"]
  to   = oci_identity_compartment.practice["gamma"]
}

resource "oci_identity_compartment" "practice" {
  for_each = {
    for key, settings in var.practice_compartments :
    key => settings
    if settings.enabled
  }

  compartment_id = oci_identity_compartment.learning.id
  name           = "learning-${each.key}"
  description    = each.value.description
  enable_delete  = true

  freeform_tags = {
    managed_by = "terraform"
    cleanup    = each.value.purpose == "temporary" ? "eligible" : "keep"
  }

  lifecycle {
    prevent_destroy = true
  }
}

