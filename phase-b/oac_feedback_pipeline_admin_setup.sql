-- ============================================================================
-- OAC AI Feedback Pipeline — ADMIN SETUP (run this first, as ADMIN)
-- ============================================================================
-- This script creates a dedicated OACFB user that owns every pipeline object.
-- ADMIN credentials are only used for this one-time setup; day-to-day the
-- pipeline runs entirely under OACFB.
--
-- Why a dedicated user:
--   * ADMIN credentials stay out of the pipeline code path.
--   * Customer security reviews are simple — one named user, minimum grants.
--   * Drop the whole pipeline in one command: DROP USER OACFB CASCADE.
--
-- Run once, as ADMIN, in Database Actions (SQL).
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. Create the OACFB user.
-- !!!! EDIT the password below BEFORE running this block. !!!!
-- Password requirements: at least 12 characters, mix of upper/lower/digit/special.
-- Save the password — you'll use it when you connect as OACFB in the next script.
-- ----------------------------------------------------------------------------
CREATE USER OACFB IDENTIFIED BY "WElcome__12345";


-- ----------------------------------------------------------------------------
-- 2. Grant privileges.
--
-- The pipeline needs two flavours of grants:
--   (A) DDL + session grants for creating objects outside any procedure.
--       Role-based grants work fine here — we use Oracle's standard DWROLE.
--   (B) Runtime grants for things the pipeline procedure touches inside
--       itself (DBMS_SODA_ADMIN, the DATA_PUMP_DIR directory).
--       These MUST be direct grants, not role-based.
--
-- Why direct grants for runtime?
-- OAC_INGEST_LOGS is a DEFINER'S-rights PL/SQL procedure (Oracle's default).
-- Definer's-rights PL/SQL uses only grants made DIRECTLY to the definer —
-- any privilege that came via a role (DWROLE, SODA_APP, etc.) is invisible
-- inside the procedure at runtime. That's why DATA_PUMP_DIR needs a direct
-- grant even though DWROLE appears to already cover it.
-- ----------------------------------------------------------------------------

-- (A) Base role: CREATE SESSION/TABLE/VIEW/PROCEDURE/JOB, UNLIMITED TABLESPACE,
--     and EXECUTE on most DBMS_* packages. Covers all DDL and ad-hoc SQL.
GRANT DWROLE                         TO OACFB;

-- (B) Runtime grants, direct — required inside the pipeline procedure:

--     DBMS_CLOUD is called by OAC_INGEST_LOGS (LIST_OBJECTS + COPY_COLLECTION).
--     DWROLE grants this via role, which is invisible inside definer's-rights PL/SQL.
GRANT EXECUTE ON DBMS_CLOUD          TO OACFB;

--     DBMS_SODA is used transitively by DBMS_CLOUD.COPY_COLLECTION.
GRANT EXECUTE ON DBMS_SODA           TO OACFB;

--     SODA_APP role enables the SODA_COLLECTION_T type and SODA runtime calls.
GRANT SODA_APP                       TO OACFB;

--     DBMS_CLOUD.COPY_COLLECTION internally calls DBMS_SODA_ADMIN,
--     which neither DWROLE nor SODA_APP grants.
GRANT EXECUTE ON DBMS_SODA_ADMIN     TO OACFB;

--     DATA_PUMP_DIR: DBMS_CLOUD stages compressed files here.
--     DWROLE grants this via role, which is invisible inside definer's-rights PL/SQL.
GRANT READ, WRITE ON DIRECTORY DATA_PUMP_DIR TO OACFB;

-- (C) Tablespace quota.
--     DWROLE grants UNLIMITED TABLESPACE (a system privilege), but in ADB
--     that's not the same as having quota on the DATA tablespace. Without
--     this explicit ALTER, INSERTs into user tables fail with ORA-01950.
ALTER USER OACFB QUOTA UNLIMITED ON DATA;


-- ----------------------------------------------------------------------------
-- 3. Enable resource principal at the database level (safe no-op if already on).
-- ----------------------------------------------------------------------------
BEGIN
  DBMS_CLOUD_ADMIN.ENABLE_RESOURCE_PRINCIPAL();
END;
/


-- ----------------------------------------------------------------------------
-- 4. Grant OACFB permission to use the resource principal credential.
-- This is what lets OACFB say credential_name => 'OCI$RESOURCE_PRINCIPAL'
-- inside DBMS_CLOUD calls with no password or API key.
-- ----------------------------------------------------------------------------
BEGIN
  DBMS_CLOUD_ADMIN.ENABLE_RESOURCE_PRINCIPAL(username => 'OACFB');
END;
/


-- ----------------------------------------------------------------------------
-- 5. Quick verification (optional)
-- ----------------------------------------------------------------------------
SELECT username, account_status, created
FROM DBA_USERS
WHERE username = 'OACFB';

SELECT owner, credential_name
FROM DBA_CREDENTIALS
WHERE username = 'OACFB'
   OR credential_name LIKE '%RESOURCE_PRINCIPAL%';


-- ============================================================================
-- NEXT STEPS
-- ============================================================================
-- You're done with ADMIN. Now:
--   1. Sign out of Database Actions (avatar/user icon → Sign Out).
--   2. Sign back in as OACFB with the password you set in step 1 above.
--   3. Database actions → SQL.
--   4. Run oac_feedback_pipeline_install.sql.
-- ============================================================================
