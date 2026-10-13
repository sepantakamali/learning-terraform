terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~>9.2"
    }
  }

  backend "oci" {
    bucket              = "learning-terraform-state"
    namespace           = "lrzw2bsg0uek"
    key                 = "environment-lab/prod/terraform.tfstate"
    region              = "uk-london-1"
    config_file_profile = "LEARNING_TERRAFORM"
  }
}

provider "oci" {
  config_file_profile = "LEARNING_TERRAFORM"
}

module "compartment" {
  source = "../modules/compartment"

  parent_compartment_id = "ocid1.compartment.oc1..aaaaaaaaqyvhurpus35zpk2w4luact3d3umrd7xnnrtsabnjoufyeedlfcca"
  environment           = "prod"
}

output "compartment_id" {
  value = module.compartment.compartment_id
}
