# Phase B — Database pipeline

One-shot Cloud Shell install. Creates the `OACFB` schema in your Autonomous Database and wires up the ingestion procedure, views, and scheduler.

## Files

| File | Role |
|---|---|
| `install_oac_feedback_pipeline.sh` | Bash installer. Runs in OCI Cloud Shell. Calls both .sql files in order and handles prompts. Idempotent. |
| `oac_feedback_pipeline_admin_setup.sql` | Run as ADMIN. Creates the `OACFB` user with the required grants. |
| `oac_feedback_pipeline_install.sql` | Run as OACFB. Creates: OCI credential, SODA collection, watermark table, ingestion procedure, `OAC_FEEDBACK_CLEAN` and `OAC_FEEDBACK_WITH_LSQL` views, and the scheduler job. |

## Prerequisites

Phase A must be complete. You'll need the `adb_location_uri` output from the Terraform Apply (it looks like `https://objectstorage.<region>.oraclecloud.com/n/<namespace>/b/oac-feedback-logs/o/oac-ai/`).

## Run it

Upload the three files to OCI Cloud Shell and run:

```bash
chmod +x install_oac_feedback_pipeline.sh
./install_oac_feedback_pipeline.sh
```

Answer the prompts: ADB OCID, ADMIN password, new OACFB password, the `adb_location_uri` from Phase A.

## Verify

In Database Actions, sign in as OACFB and run:

```sql
SELECT COUNT(*) FROM OAC_FEEDBACK_WITH_LSQL WHERE ts > SYSTIMESTAMP - INTERVAL '1' HOUR;
SELECT event_bucket, COUNT(*) FROM OAC_FEEDBACK_WITH_LSQL GROUP BY event_bucket;
```

First check should return a non-zero count (the scheduler runs on the connector's default cadence — first rows arrive within ~5 minutes). Second check should show no `unknown` bucket.
