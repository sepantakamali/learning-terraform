terraform {
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~>2.5"
    }
  }
}

resource "local_file" "hello" {
  filename        = "${path.module}/hello.txt"
  content         = "I am learning Terraform.\n"
  file_permission = "0644"
}

