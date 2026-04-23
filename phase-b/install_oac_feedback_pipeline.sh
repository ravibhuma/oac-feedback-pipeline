#!/bin/bash
# ============================================================================
# deploy-phase2.sh — Cloud Shell one-shot deployer for Phase 2
# ============================================================================
# Runs the entire database side of Phase 2 in one go:
#   1. Downloads the ADB wallet via OCI CLI
#   2. Handles pre-existing OACFB user (prompts to drop + recreate)
#   3. Connects as ADMIN and runs oac_feedback_pipeline_admin_setup.sql
#   4. Connects as OACFB and runs oac_feedback_pipeline_install.sql
#   5. Prints verification output and next-step instructions for OAC
#
# Environment: OCI Cloud Shell (has OCI CLI, SQLcl, python3 preinstalled).
# ============================================================================

set -euo pipefail

# ---- Pretty output helpers ----
R='\033[0;31m'; G='\033[0;32m'; Y='\033[0;33m'; B='\033[0;36m'; N='\033[0m'
heading() { echo -e "\n${B}═══ $* ═══${N}"; }
ok()      { echo -e "${G}✓${N} $*"; }
warn()    { echo -e "${Y}⚠${N} $*"; }
fail()    { echo -e "${R}✗${N} $*" >&2; exit 1; }

# ============================================================================
# 1. Prerequisites
# ============================================================================
heading "Checking prerequisites"

for cmd in oci sql unzip openssl python3; do
  command -v "$cmd" >/dev/null 2>&1 || fail "$cmd not found. Run this script from OCI Cloud Shell."
done
ok "OCI CLI, SQLcl, unzip, openssl, python3 all present"

for f in oac_feedback_pipeline_admin_setup.sql oac_feedback_pipeline_install.sql; do
  [ -f "$f" ] || fail "Required file '$f' not found in current directory. Change into the OAC-Logs-Automation folder first."
done
ok "Required SQL files found"

# ============================================================================
# 2. Gather inputs
# ============================================================================
heading "Configuration"

read -rp "Autonomous Database OCID (ocid1.autonomousdatabase.oc1...): " ADB_OCID
[[ "$ADB_OCID" == ocid1.autonomousdatabase.* ]] || fail "Not a valid ADB OCID"

read -rsp "Current ADB ADMIN password: " ADMIN_PWD; echo
[ -n "$ADMIN_PWD" ] || fail "ADMIN password cannot be empty"

echo
echo "The script will create a new OACFB user. Choose a strong password:"
echo "  - At least 12 characters"
echo "  - Mix of upper, lower, digit, and special"
echo "  - Avoid & $ \\ for easiest substitution (though the script now handles them)"
read -rsp "New OACFB password: "      OACFB_PWD;  echo
read -rsp "Confirm OACFB password: "  OACFB_PWD2; echo
[ "$OACFB_PWD" = "$OACFB_PWD2" ] || fail "Passwords don't match"
[ "${#OACFB_PWD}" -ge 12 ]      || fail "Password must be at least 12 characters"

echo
echo "Phase 1 output — the adb_location_uri value (also known as the bucket URI)."
echo "It's the Object Storage URL where Phase 1 writes log files."
echo "It looks like: https://objectstorage.<region>.oraclecloud.com/n/<ns>/b/<bucket>/o/<prefix>/"
read -rp "adb_location_uri (must end with /): " BUCKET_URI
[[ "$BUCKET_URI" == https://objectstorage.*/ ]] || fail "adb_location_uri must start with https://objectstorage. and end with /"

ok "All inputs validated"

# ============================================================================
# 3. Download ADB wallet
# ============================================================================
heading "Downloading ADB wallet"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

WALLET_ZIP="$TMPDIR/wallet.zip"
WALLET_DIR="$TMPDIR/wallet"
WALLET_PWD="$(openssl rand -base64 24 | tr -d '/=+')Aa1!"
mkdir -p "$WALLET_DIR"

oci db autonomous-database generate-wallet \
  --autonomous-database-id "$ADB_OCID" \
  --password "$WALLET_PWD" \
  --file "$WALLET_ZIP" >/dev/null || fail "Wallet download failed. Check the ADB OCID and your permissions."
ok "Wallet downloaded"

unzip -o -q "$WALLET_ZIP" -d "$WALLET_DIR"
export TNS_ADMIN="$WALLET_DIR"
ok "Wallet unpacked (TNS_ADMIN=$WALLET_DIR)"

DB_SERVICE="$(grep -oE '^[[:space:]]*[A-Za-z0-9_]+_low\b' "$WALLET_DIR/tnsnames.ora" | head -1 | tr -d ' ')"
[ -n "$DB_SERVICE" ] || fail "Could not find a _low TNS service in tnsnames.ora"
ok "Using TNS service: $DB_SERVICE"

# ============================================================================
# 4. Check if OACFB exists; handle gracefully
# ============================================================================
heading "Checking if OACFB user already exists"

OACFB_EXISTS_RAW="$(sql -S -L "ADMIN/$ADMIN_PWD@$DB_SERVICE" <<EOF || true
SET FEEDBACK OFF HEADING OFF PAGESIZE 0 ECHO OFF
SELECT COUNT(*) FROM DBA_USERS WHERE username = 'OACFB';
EXIT;
EOF
)"
OACFB_EXISTS="$(echo "$OACFB_EXISTS_RAW" | tr -d '[:space:]')"

if [ "$OACFB_EXISTS" = "1" ]; then
  warn "OACFB user already exists in this database."
  echo "  Options:"
  echo "    (d) Drop OACFB CASCADE (removes user + everything they own) and re-create"
  echo "    (a) Abort — keep the existing user; re-run manually if you want to use it"
  read -rp "Choice [d/a]: " choice
  case "$choice" in
    d|D)
      echo "Dropping OACFB (handles active sessions automatically)..."
      sql -S -L "ADMIN/$ADMIN_PWD@$DB_SERVICE" <<'EOF'
-- 1. Drop scheduler job first (it spawns OACFB sessions every minute)
BEGIN
  DBMS_SCHEDULER.DROP_JOB(job_name => 'OACFB.OAC_LOG_INGEST_JOB', force => TRUE);
EXCEPTION WHEN OTHERS THEN NULL;
END;
/

-- 2. Kill any active OACFB sessions
BEGIN
  FOR s IN (SELECT sid, serial# FROM v$session WHERE username = 'OACFB') LOOP
    BEGIN
      EXECUTE IMMEDIATE 'ALTER SYSTEM KILL SESSION ''' || s.sid || ',' || s.serial# || ''' IMMEDIATE';
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END LOOP;
END;
/

-- 3. Drop the user
DROP USER OACFB CASCADE;

EXIT;
EOF
      ok "OACFB dropped (scheduler job + sessions cleaned up)"
      ;;
    *)
      fail "Aborted. Use the existing OACFB or drop it manually, then re-run."
      ;;
  esac
else
  ok "OACFB does not exist — fresh install"
fi

# ============================================================================
# 5. Prepare SQL files (substitute values + append EXIT;)
#    Uses python3 (not sed) so special characters in passwords are safe.
# ============================================================================
heading "Preparing SQL files"

cp oac_feedback_pipeline_admin_setup.sql "$TMPDIR/admin_setup.sql"
cp oac_feedback_pipeline_install.sql     "$TMPDIR/install.sql"

OACFB_PWD="$OACFB_PWD" BUCKET_URI="$BUCKET_URI" TMPDIR="$TMPDIR" \
python3 - <<'PYEOF'
import os, re

pwd  = os.environ['OACFB_PWD']
uri  = os.environ['BUCKET_URI']
tdir = os.environ['TMPDIR']

# --- admin_setup.sql: replace OACFB password, append EXIT ---
p = f"{tdir}/admin_setup.sql"
with open(p) as f: c = f.read()
c = re.sub(r'IDENTIFIED BY "[^"]*"', 'IDENTIFIED BY "' + pwd + '"', c)
if not c.rstrip().endswith("EXIT;"):
    c = c.rstrip() + "\n\nEXIT;\n"
with open(p, "w") as f: f.write(c)

# --- install.sql: replace bucket URI, append EXIT ---
p = f"{tdir}/install.sql"
with open(p) as f: c = f.read()
c = re.sub(r"'https://objectstorage[^']*'", "'" + uri + "'", c)
if not c.rstrip().endswith("EXIT;"):
    c = c.rstrip() + "\n\nEXIT;\n"
with open(p, "w") as f: f.write(c)
PYEOF

ok "Temporary SQL files prepared"

# ============================================================================
# 6. Run admin_setup.sql as ADMIN
# ============================================================================
heading "Running admin_setup.sql as ADMIN"

if sql -S -L "ADMIN/$ADMIN_PWD@$DB_SERVICE" @"$TMPDIR/admin_setup.sql"; then
  ok "Admin setup completed"
else
  fail "Admin setup failed. See SQLcl output above."
fi

# ============================================================================
# 7. Run install.sql as OACFB
# ============================================================================
heading "Running install.sql as OACFB"

if sql -S -L "OACFB/$OACFB_PWD@$DB_SERVICE" @"$TMPDIR/install.sql"; then
  ok "Install completed"
else
  fail "Install failed. See SQLcl output above."
fi

# ============================================================================
# 8. Verify
# ============================================================================
heading "Verification"

sql -S -L "OACFB/$OACFB_PWD@$DB_SERVICE" <<'EOSQL'
SET HEADING ON PAGESIZE 100
PROMPT -- Row count in raw log collection
SELECT COUNT(*) AS oac_logs_row_count FROM OAC_LOGS;

PROMPT -- Scheduler job status
SELECT job_name, enabled, state, TO_CHAR(next_run_date, 'YYYY-MM-DD HH24:MI:SS') AS next_run
  FROM USER_SCHEDULER_JOBS
 WHERE job_name = 'OAC_LOG_INGEST_JOB';
EXIT;
EOSQL

KEEP_WALLET_ZIP="$HOME/oacfb-wallet.zip"
cp "$WALLET_ZIP" "$KEEP_WALLET_ZIP"

# ============================================================================
# 9. Next steps
# ============================================================================
heading "Phase 2 database side is deployed"

cat <<EONEXT

Remaining manual steps (OAC workbook — GUI-only in OAC):

  1. Wallet saved at:  $KEEP_WALLET_ZIP
     Download it: Cloud Shell hamburger (top-left) → Download → pick the file.

  2. In OAC:
     Data → Connections → Create → Oracle Autonomous Data Warehouse
       - Upload the wallet:   $KEEP_WALLET_ZIP
       - Username:            OACFB
       - Password:            (the OACFB password you just set)
       - Service name:        $DB_SERVICE

  3. In OAC:
     Create → Dataset → pick the connection → schema OACFB →
     select OAC_FEEDBACK_WITH_LSQL → Save

  4. Build your workbook. See the Phase 2 blog for recommended visualizations.

To re-run a manual ingest (any time, without re-running this whole script):

  sql OACFB/<password>@$DB_SERVICE <<'SQL'
    BEGIN OAC_INGEST_LOGS; END;
    /
  SQL

EONEXT
