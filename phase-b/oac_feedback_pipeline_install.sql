-- ============================================================================
-- OAC AI Assistant Feedback Pipeline — Install (run as OACFB)
-- Based on: https://oac-ai.github.io/oac-ai-workshops/ai-feedback-guide.html
--
-- PREREQUISITES
-- 1. Phase 1 complete: files landing in your Object Storage bucket.
-- 2. oac_feedback_pipeline_admin_setup.sql has been run ONCE as ADMIN.
--    (That script creates the OACFB user and enables resource principal.)
-- 3. You are signed into Database Actions as OACFB (not ADMIN).
-- 4. The location URI in Step B-4 below matches your Phase 1 output.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- B-1 · Safety check: confirm we're running as OACFB, not ADMIN.
-- Running this file as ADMIN will still work, but it will put the pipeline
-- objects in the ADMIN schema — which defeats the point of the OACFB user.
-- ----------------------------------------------------------------------------
DECLARE
  v_user VARCHAR2(128);
BEGIN
  SELECT USER INTO v_user FROM DUAL;
  IF v_user != 'OACFB' THEN
    RAISE_APPLICATION_ERROR(
      -20001,
      'This script should be run as the OACFB user. Currently connected as: '
      || v_user
      || '. Run oac_feedback_pipeline_admin_setup.sql once as ADMIN first, '
      || 'then sign in as OACFB and re-run this script.'
    );
  END IF;
END;
/


-- ----------------------------------------------------------------------------
-- B-2 · Create the SODA collection that holds raw log events
-- ----------------------------------------------------------------------------
DECLARE
  l_collection SODA_COLLECTION_T;
BEGIN
  l_collection := DBMS_SODA.CREATE_COLLECTION('OAC_LOGS');
END;
/


-- ----------------------------------------------------------------------------
-- B-3 · Watermark table: remembers the timestamp of the last ingestion
-- ----------------------------------------------------------------------------
CREATE TABLE OAC_LOG_TIMESTAMP_UPDATE (
  last_processed_time TIMESTAMP DEFAULT TIMESTAMP '1970-01-01 00:00:00'
);

INSERT INTO OAC_LOG_TIMESTAMP_UPDATE VALUES (TIMESTAMP '1970-01-01 00:00:00');
COMMIT;


-- ----------------------------------------------------------------------------
-- B-4 · Ingestion procedure
-- !!!!  EDIT the v_uri_prefix line below before running this block  !!!!
-- Paste the adb_location_uri from Phase 1. It MUST end with a trailing slash.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE OAC_INGEST_LOGS
  -- Use invoker's rights so role-based grants (DWROLE, SODA_APP, etc.)
  -- apply at runtime. Without this, COPY_COLLECTION hits ORA-01031.
  AUTHID CURRENT_USER
AS
  v_last_loaded TIMESTAMP;
  v_uri_prefix  CONSTANT VARCHAR2(4000) :=
    'https://objectstorage.us-ashburn-1.oraclecloud.com/n/idseylbmv0mm/b/oac-feedback-logs/o/oac-ai/';
BEGIN
  SELECT last_processed_time INTO v_last_loaded FROM OAC_LOG_TIMESTAMP_UPDATE;

  FOR obj IN (
    SELECT object_name, created
      FROM DBMS_CLOUD.LIST_OBJECTS('OCI$RESOURCE_PRINCIPAL', v_uri_prefix)
     WHERE created > v_last_loaded
     ORDER BY created
  ) LOOP
    DBMS_CLOUD.COPY_COLLECTION(
      collection_name => 'OAC_LOGS',
      credential_name => 'OCI$RESOURCE_PRINCIPAL',
      file_uri_list   => v_uri_prefix || obj.object_name,
      format          => JSON_OBJECT(
                           'recorddelimiter' VALUE '''\n''',
                           'compression'     VALUE 'auto'
                         )
    );
  END LOOP;

  UPDATE OAC_LOG_TIMESTAMP_UPDATE SET last_processed_time = SYSTIMESTAMP;
  COMMIT;
END;
/


-- ----------------------------------------------------------------------------
-- B-5 · Log details view: exposes JSON fields as SQL columns
-- Note: the SODA payload column is usually named "data" (shown below).
-- Some ADB configurations use "json_document" instead. If this CREATE VIEW
-- fails with ORA-00904 (invalid identifier), swap every "data" below to
-- "json_document" and re-run. Verify which your collection uses with:
--   SELECT column_name FROM USER_TAB_COLS WHERE table_name = 'OAC_LOGS';
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW OAC_LOG_DETAILS AS
SELECT
  JSON_VALUE(data, '$.oracle.tenantid')                           AS tenant_id,
  JSON_VALUE(data, '$.oracle.compartmentid')                      AS compartment_id,
  JSON_VALUE(data, '$.data.category')                             AS category,
  JSON_VALUE(data, '$.data.message')                              AS message,
  JSON_VALUE(data, '$.data.additionalDetails.feedback')           AS feedback,
  JSON_VALUE(data, '$.data.additionalDetails.feedbackCategory')   AS feedback_category,
  JSON_VALUE(data, '$.data.additionalDetails.feedbackDetails')    AS feedback_details,
  JSON_VALUE(data, '$.data.additionalDetails.utterance')          AS utterance,
  JSON_VALUE(data, '$.data.additionalDetails.datamodelName')      AS datamodel_name,
  JSON_VALUE(data, '$.data.additionalDetails.userId')             AS user_id,
  JSON_VALUE(data, '$.data.ecid')                                 AS ecid,
  JSON_VALUE(data, '$.data.additionalDetails.parentEcid')         AS parent_ecid,
  TO_TIMESTAMP(JSON_VALUE(data, '$.time'),
               'YYYY-MM-DD"T"HH24:MI:SS.FF3"Z"')                           AS event_time
FROM OAC_LOGS;


-- ----------------------------------------------------------------------------
-- B-6 · Feedback analysis view
-- Correlates each feedback event with its originating request event.
--
-- Note on OAC's feedback JSON:
--   additionalDetails.feedback         = 'positive' | 'negative'    (sentiment)
--   additionalDetails.feedbackCategory = NULL for positives,
--                                        a reason code for negatives
--                                        (INCORRECT_ANSWER, IRRELEVANT_ANSWER, ...)
-- So we derive sentiment from f.feedback (the authoritative field) and keep the
-- original reason code in a separate column, feedback_reason.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW OAC_AI_FEEDBACK_ANALYSIS AS
SELECT
  f.user_id,
  f.utterance,
  f.datamodel_name,
  f.feedback,
  CASE
    WHEN LOWER(f.feedback) = 'positive' OR LOWER(f.feedback) LIKE '%up%'   THEN 'positive'
    WHEN LOWER(f.feedback) = 'negative' OR LOWER(f.feedback) LIKE '%down%' THEN 'negative'
    WHEN LOWER(f.feedback_category) LIKE '%positive%' THEN 'positive'
    WHEN LOWER(f.feedback_category) LIKE '%negative%' THEN 'negative'
    ELSE 'unknown'
  END                               AS feedback_category,
  f.feedback_category               AS feedback_reason,
  f.feedback_details,
  f.event_time                      AS feedback_time,
  f.ecid                            AS feedback_ecid,
  f.parent_ecid,
  r.event_time                      AS request_time,
  r.ecid                            AS request_ecid,
  ROUND(EXTRACT(DAY    FROM (f.event_time - r.event_time)) * 86400 +
        EXTRACT(HOUR   FROM (f.event_time - r.event_time)) * 3600  +
        EXTRACT(MINUTE FROM (f.event_time - r.event_time)) * 60    +
        EXTRACT(SECOND FROM (f.event_time - r.event_time)), 3)    AS elapsed_time
FROM OAC_LOG_DETAILS f
LEFT JOIN OAC_LOG_DETAILS r
  ON SUBSTR(r.ecid, 1, 36) = SUBSTR(f.parent_ecid, 1, 36)
WHERE f.feedback IS NOT NULL;


-- ----------------------------------------------------------------------------
-- B-7 · LSQL correlation view
-- Joins each feedback event with the Logical SQL the AI Assistant generated.
--
-- Why time-proximity instead of an ECID join:
-- In some tenancies (notably when feedback comes through the GenAI subsystem)
-- the ECID on a feedback event does not match the ECID on the corresponding
-- "SQL Request" log line. Correlating by time window is more robust:
--   - pick the most recent "SQL Request" line for the same user
--   - within a 10-minute window ending at the feedback timestamp
--   - collapse ties with ROW_NUMBER so each feedback row gets exactly one LSQL
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW OAC_FEEDBACK_WITH_LSQL AS
WITH ranked AS (
  SELECT
    f.user_id,
    f.utterance,
    f.feedback,
    f.feedback_category,
    f.feedback_reason,
    f.feedback_details,
    f.datamodel_name,
    f.elapsed_time,
    f.request_time,
    f.feedback_time,
    f.feedback_ecid,
    l.message                                                               AS lsql_msg,
    ROW_NUMBER() OVER (
      PARTITION BY f.feedback_ecid
      ORDER BY l.event_time DESC NULLS LAST
    )                                                                       AS rn
  FROM OAC_AI_FEEDBACK_ANALYSIS f
  LEFT JOIN OAC_LOG_DETAILS l
    ON l.user_id = f.user_id
   AND l.event_time BETWEEN f.feedback_time - INTERVAL '10' MINUTE
                        AND f.feedback_time
   AND l.message LIKE '%SQL Request%'
   AND l.message LIKE '%SELECT%'
)
SELECT
  user_id,
  utterance,
  feedback,
  feedback_category,
  feedback_reason,
  feedback_details,
  datamodel_name,
  elapsed_time,
  request_time,
  feedback_time,
  CASE WHEN lsql_msg IS NOT NULL
       THEN SUBSTR(lsql_msg, INSTR(lsql_msg, 'SELECT'), 3000)
       ELSE NULL
  END                                                                       AS lsql,
  REGEXP_SUBSTR(lsql_msg, 'logical request hash:\s*(\w+)', 1, 1, 'i', 1)    AS lsql_hash
FROM ranked
WHERE rn = 1;


-- ----------------------------------------------------------------------------
-- B-8 · Scheduler job: runs OAC_INGEST_LOGS once a minute
-- Idempotent: drops an existing job with the same name before creating,
-- so re-running this script is safe.
-- ----------------------------------------------------------------------------
BEGIN
  BEGIN
    DBMS_SCHEDULER.DROP_JOB(job_name => 'OAC_LOG_INGEST_JOB', force => TRUE);
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLCODE != -27475 THEN  -- -27475 = job does not exist (ignore)
        RAISE;
      END IF;
  END;

  DBMS_SCHEDULER.CREATE_JOB(
    job_name        => 'OAC_LOG_INGEST_JOB',
    job_type        => 'PLSQL_BLOCK',
    job_action      => 'BEGIN OAC_INGEST_LOGS; END;',
    repeat_interval => 'FREQ=MINUTELY; INTERVAL=1',
    enabled         => TRUE
  );
END;
/


-- ============================================================================
-- VERIFICATION — run these after the install to confirm the pipeline works
-- ============================================================================

-- Trigger one manual ingest right now (don't wait for the scheduler)
BEGIN
  OAC_INGEST_LOGS;
END;
/

-- Did any rows land?
SELECT COUNT(*) AS log_row