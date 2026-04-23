###############################################################################
# OAC AI feedback pipeline - OCI infrastructure
#
# Provisions:
#   * a log group
#   * an OAC service (diagnostic) log
#   * an Object Storage bucket
#   * a dynamic group for the target Autonomous Database
#   * policies that let the ADB read the bucket via resource principal
#   * a Service Connector Hub that forwards the log to the bucket
###############################################################################

terraform {
  required_version = ">= 1.3.0"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 5.0.0"
    }
  }
}

provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid != "" ? var.user_ocid : null
  fingerprint      = var.fingerprint != "" ? var.fingerprint : null
  private_key_path = var.private_key_path != "" ? var.private_key_path : null
  region           = var.region
}

# -----------------------------------------------------------------------------
# Object Storage namespace and bucket
# -----------------------------------------------------------------------------

data "oci_objectstorage_namespace" "ns" {
  compartment_id = var.tenancy_ocid
}

locals {
  namespace          = var.bucket_namespace != "" ? var.bucket_namespace : data.oci_objectstorage_namespace.ns.namespace
  enable_adb_policy  = var.adb_ocid != ""
}

resource "oci_objectstorage_bucket" "feedback" {
  compartment_id        = var.compartment_ocid
  namespace             = local.namespace
  name                  = var.bucket_name
  access_type           = "NoPublicAccess"
  object_events_enabled = false
  storage_tier          = "Standard"
  versioning            = "Disabled"
}

# -----------------------------------------------------------------------------
# Logging: log group + OAC service log
# -----------------------------------------------------------------------------

resource "oci_logging_log_group" "oac" {
  compartment_id = var.compartment_ocid
  display_name   = "${var.name_prefix}-oac-loggroup"
  description    = "Log group for OAC AI feedback automation"
}

resource "oci_logging_log" "oac_service_log" {
  display_name       = "${var.name_prefix}-oac-diag-log"
  log_group_id       = oci_logging_log_group.oac.id
  log_type           = "SERVICE"
  is_enabled         = true
  retention_duration = var.log_retention_days

  configuration {
    # Values verified against Oracle's official Terraform module:
    # github.com/oracle-terraform-modules/terraform-oci-logging (modules/analyticscloud)
    source {
      category    = "diagnostic"
      resource    = var.oac_instance_ocid
      service     = "oacnativeproduction"
      source_type = "OCISERVICE"
    }
    compartment_id = var.compartment_ocid
  }
}

# -----------------------------------------------------------------------------
# Service Connector Hub: Logging -> Object Storage
# -----------------------------------------------------------------------------

resource "oci_sch_service_connector" "oac_to_bucket" {
  compartment_id = var.compartment_ocid
  display_name   = "${var.name_prefix}-oac-log-to-bucket"
  description    = "Forwards OAC AI feedback logs to Object Storage"
  source {
    kind = "logging"
    log_sources {
      compartment_id = var.compartment_ocid
      log_group_id   = oci_logging_log_group.oac.id
      log_id         = oci_logging_log.oac_service_log.id
    }
  }
  target {
    kind               = "objectStorage"
    bucket             = oci_objectstorage_bucket.feedback.name
    namespace          = local.namespace
    object_name_prefix = trimsuffix(var.object_prefix, "/")
    batch_size_in_kbs  = 5000
    batch_time_in_sec  = 60
  }
}

# -----------------------------------------------------------------------------
# Dynamic group + policies for ADB resource principal
# -----------------------------------------------------------------------------

resource "oci_identity_dynamic_group" "adb_rp" {
  count          = local.enable_adb_policy ? 1 : 0
  compartment_id = var.tenancy_ocid
  name           = "${var.name_prefix}-adb-rp-dg"
  description    = "Resource principal dynamic group for the OAC feedback ADB"
  matching_rule  = "ALL {resource.type = 'autonomousdatabase', resource.id = '${var.adb_ocid}'}"
}

resource "oci_identity_policy" "adb_bucket_read" {
  count          = local.enable_adb_policy ? 1 : 0
  compartment_id = var.compartment_ocid
  name           = "${var.name_prefix}-adb-read-bucket"
  description    = "Lets the OAC feedback ADB read from the feedback bucket via resource principal"
  statements = [
    "Allow dynamic-group ${oci_identity_dynamic_group.adb_rp[0].name} to read buckets in compartment id ${var.compartment_ocid} where target.bucket.name = '${oci_objectstorage_bucket.feedback.name}'",
    "Allow dynamic-group ${oci_identity_dynamic_group.adb_rp[0].name} to read objects in compartment id ${var.compartment_ocid} where target.bucket.name = '${oci_objectstorage_bucket.feedback.name}'"
  ]
}

# Lets the Service Connector Hub service write log files into the bucket.
# Without this, the connector stays Active but silently drops everything.
resource "oci_identity_policy" "sch_write_bucket" {
  compartment_id = var.compartment_ocid
  name           = "${var.name_prefix}-sch-write-bucket"
  description    = "Lets Service Connector Hub write OAC log files into the feedback bucket"
  statements = [
    "Allow any-user to manage objects in compartment id ${var.compartment_ocid} where all {request.principal.type='serviceconnector', target.bucket.name='${oci_objectstorage_bucket.feedback.name}', request.principal.compartment.id='${var.compartment_ocid}'}"
  ]
}

# -----------------------------------------------------------------------------
# Outputs used by the SQL installer and the web app
# -----------------------------------------------------------------------------

locals {
  location_uri = format(
    "https://objectstorage.%s.oraclecloud.com/n/%s/b/%s/o/%s",
    var.region,
    local.namespace,
    oci_objectstorage_bucket.feedback.name,
    var.object_prefix
  )
}
