# Terraform: OCI side of the OAC AI feedback pipeline

This stack stands up the OCI resources the SQL pipeline depends on:

- Log group and OAC service (diagnostic) log
- Object Storage bucket
- Service Connector Hub routing log -> bucket
- Dynamic group and policy so the ADB resource principal can read the bucket

## Usage

```
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars
terraform init
terraform plan
terraform apply
```

Terraform prints `adb_location_uri`. Paste that value into `p_location_uri`
in `oac_feedback_pipeline_install.sql` and then run the SQL installer in
the Autonomous Database.

## Notes

- OAC service-log `category` may differ by region and OAC version. If the
  `oci_logging_log` resource fails with `InvalidCategory`, look up the valid
  category names with `oci logging-service resource-type list` and adjust the
  `category` attribute in `main.tf`.
- The dynamic group is scoped to exactly one ADB OCID so no other databases
  can use this policy.
- The bucket is created with `NoPublicAccess`. Do not flip that to public.
