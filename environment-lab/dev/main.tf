terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~>9.2"
    }
  }

  backend "oci" {
    bucket    = "learning-terraform-state"
    namespace = "lrzw2bsg0uek"
    key       = "environment-lab/dev/terraform.tfstate"
    region    = "uk-london-1"
  }
}

provider "oci" {}

provider "oci" {
  alias  = "london"
  region = "uk-london-1"
}

module "compartment" {
  source = "../modules/compartment"

  parent_compartment_id = data.terraform_remote_state.foundation.outputs.oci_lab_compartment_id
  environment           = "dev"

  providers = {
    oci = oci.london
  }

  description = "Development compartment deployed through approved GitHub Actions"
  owner       = "platform-team"
}

output "compartment_id" {
  value = module.compartment.compartment_id
}
