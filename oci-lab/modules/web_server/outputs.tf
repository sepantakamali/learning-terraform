output "public_ip" {
  value = oci_core_instance.web.public_ip
}

output "private_ip" {
  value = oci_core_instance.web.private_ip
}
