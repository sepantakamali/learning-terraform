terraform {
  backend "oci" {
    bucket              = "learning-terraform-state"
    namespace           = "lrzw2bsg0uek"
    key                 = "oci-lab/terraform.tfstate"
    region              = "uk-london-1"
    config_file_profile = "LEARNING_TERRAFORM"
  }
}
