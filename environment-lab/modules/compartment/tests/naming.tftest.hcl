mock_provider "oci" {}

run "development_name" {
  command = plan

  variables {
    parent_compartment_id = "oci1.compartment.oc1..test"
    environment           = "dev"
  }

  assert {
    condition     = oci_identity_compartment.compartment.name == "learning-env-dev"
    error_message = "Development compartment must be named learnig-env-dev."
  }
}

run "production_name" {
  command = plan

  variables {
    parent_compartment_id = "ocid1.compartment.oc1..test"
    environment           = "prod"
  }

  assert {
    condition     = oci_identity_compartment.compartment.name == "learning-env-prod"
    error_message = "Production compartment must be named learning-env-prod."
  }
}
