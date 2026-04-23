output "bucket_name" {
  description = "Object Storage bucket that receives OAC log files."
  value       = oci_objectstorage_bucket.feedback.name
}

output "bucket_namespace" {
  description = "Object Storage namespace."
  value       = local.namespace
}

output "log_group_ocid" {
  value = oci_logging_log_group.oac.id
}

output "log_ocid" {
  value = oci_logging_log.oac_service_log.id
}

output "service_connector_ocid" {
  value = oci_sch_service_connector.oac_to_bucket.id
}

output "dynamic_group_name" {
  value       = length(oci_identity_dynamic_group.adb_rp) > 0 ? oci_identity_dynamic_group.adb_rp[0].name : null
  description = "Null if adb_ocid was not set."
}

output "policy_ocid" {
  value       = length(oci_identity_policy.adb_bucket_read) > 0 ? oci_identity_policy.adb_bucket_read[0].id : null
  description = "Null if adb_ocid was not set."
}

output "adb_location_uri" {
  description = "Paste this into OAC_FB_PIPELINE_PKG.CONFIGURE(p_location_uri => ...)."
  value       = local.location_uri
}
