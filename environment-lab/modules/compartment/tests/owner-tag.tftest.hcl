mock_provider "oci" {}

run "development_tag_supplied" {
  command = plan

  variables {
    parent_compartment_id = "ocid1.compartment.oc1..test"
    environment           = "dev"
    description           = "Testing supplied ownership tag behaviour on a mock dev environment compartment."
    owner                 = "platform-team"
  }

  assert {
    condition     = oci_identity_compartment.compartment.freeform_tags["owner"] == "platform-team"
    error_message = "dev compartment's owner tag differs from input owner tag."
  }
}

run "development_tag_omitted" {
  command = apply

  variables {
    parent_compartment_id = "ocid1.compartment.oc1..test"
    environment           = "dev"
    description           = "Testing omitted ownership tag behaviour on a mock dev environment compartment."
  }

  assert {
    condition     = !contains(keys(coalesce(oci_identity_compartment.compartment.freeform_tags, {})), "owner")
    error_message = "Omitting owner must not produce an owner tag."
  }
}

run "development_tag_invalid" {
  command = plan

  variables {
    parent_compartment_id = "ocid1.compartment.oc1..test"
    environment           = "dev"
    description           = "Testing invalid ownership tag behaviour on a mock dev environment compartment."
    owner                 = "   "
  }

  expect_failures = [var.owner]
}
