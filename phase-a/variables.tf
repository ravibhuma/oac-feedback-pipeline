###############################################################################
# Inputs for the OAC AI feedback pipeline infrastructure.
# All values are required unless a default is shown.
###############################################################################

variable "tenancy_ocid" {
  description = "OCID of the tenancy."
  type        = string
}

variable "user_ocid" {
  description = "OCID of the user used by Terraform. Leave empty if using instance or resource principal."
  type        = string
  default     = ""
}

variable "fingerprint" {
  description = "API signing key fingerprint. Leave empty if using instance or resource principal."
  type        = string
  default     = ""
}

variable "private_key_path" {
  description = "Path to the API signing private key. Leave empty if using instance or resource principal."
  type        = string
  default     = ""
}

variable "region" {
  description = "OCI region, e.g. us-chicago-1."
  type        = string
}

variable "compartment_ocid" {
  description = "OCID of the compartment where OCI resources will be created."
  type        = string
}

variable "oac_instance_ocid" {
  description = "OCID of the Oracle Analytics Cloud instance whose logs will be captured."
  type        = string
}

variable "adb_ocid" {
  description = <<-EOT
    OCID of the target Autonomous Database. Used only to scope the
    dynamic group and policy that let the ADB read the bucket via
    resource principal. Leave empty for an infra-only test
    (OAC -> Logging -> Object Storage); the dynamic group and policy
    will be skipped. Set it before you run the database phase.
  EOT
  type        = string
  default     = ""
}

variable "name_prefix" {
  description = "Prefix applied to all created resources. Keep it short and lowercase."
  type        = string
  default     = "oacfb"
}

variable "log_retention_days" {
  description = "Retention (in days) for the OAC service log."
  type        = number
  default     = 30
}

variable "bucket_name" {
  description = "Name of the Object Storage bucket that Connector Hub will write to."
  type        = string
  default     = "oac-feedback-logs"
}

variable "bucket_namespace" {
  description = "Optional explicit Object Storage namespace. Leave empty to auto-detect from the tenancy."
  type        = string
  default     = ""
}

variable "object_prefix" {
  description = "Object Storage key prefix for log files. End with a trailing slash."
  type        = string
  default     = "oac-ai/"
}
