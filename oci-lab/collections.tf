locals {
  practice_compartments = {
    alpha = "First practice compartment"
    gamma = "Second practice compartment"
  }
}

moved {
  from = oci_identity_compartment.practice["beta"]
  to   = oci_identity_compartment.practice["gamma"]
}

resource "oci_identity_compartment" "practice" {
  for_each = local.practice_compartments

  compartment_id = oci_identity_compartment.learning.id
  name           = "learning-${each.key}"
  description    = each.value
  enable_delete  = true

  lifecycle {
    prevent_destroy = true
  }
}

