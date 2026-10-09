resource "oci_identity_compartment" "import_practice" {
  compartment_id = oci_identity_compartment.learning.id
  name           = "learning-import-practice"
  description    = "Compartment for practicing Terraform import"
  enable_delete  = true
}

import {
  to = oci_identity_compartment.import_practice
  id = "ocid1.compartment.oc1..aaaaaaaamlasthcynkg2wuubre5ubidtvklotpfojinem7eollhzxmxc7lsq"
}
