#!/usr/bin/env bash
set -euo pipefail

# ------------------------------
# Config + Globals
# ------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/backup.config"
LOG_FILE="$SCRIPT_DIR/backup.log"
LOCK_FILE="/tmp/backup.lock"
DRY_RUN=false

# Timestamp helpers (use system timezone)
now_ts() { date +"%Y-%m-%d %H:%M:%S"; }
ts_slug() { date +"%Y-%m-%d-%H%M"; }  # e.g., 2024-11-03-1430

log() {
  # $1 level, $2 message
  local level="$1"; shift
  local msg="$*"
  printf "[%s] %s: %s\n" "$(now_ts)" "$level" "$msg" | tee -a "$LOG_FILE"
}

fail() { log "ERROR" "$*"; exit 1; }

usage() {
  cat <<USAGE
Usage:
  $0 [--dry-run] <SOURCE_FOLDER>

Examples:
  $0 /home/user/my_documents
  $0 --dry-run /home/user/my_documents
USAGE
}

# ------------------------------
# Parse args
# ------------------------------
SOURCE=""
if [[ $# -eq 0 ]]; then usage; exit 1; fi
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) SOURCE="$1"; shift ;;
  esac
done

[[ -d "${SOURCE:-}" ]] || fail "Source folder not found: ${SOURCE:-<empty>}"

# ------------------------------
# Load config
# ------------------------------
[[ -f "$CONFIG_FILE" ]] || fail "Config file not found: $CONFIG_FILE"
# shellcheck disable=SC1090
source "$CONFIG_FILE"

: "${BACKUP_DESTINATION:?BACKUP_DESTINATION is required in config}"
: "${DAILY_KEEP:?DAILY_KEEP is required in config}"
: "${WEEKLY_KEEP:?WEEKLY_KEEP is required in config}"
: "${MONTHLY_KEEP:?MONTHLY_KEEP is required in config}"

mkdir -p "$BACKUP_DESTINATION"

# Build tar --exclude args from comma list
IFS=',' read -r -a EXCLUDES <<< "${EXCLUDE_PATTERNS:-}"
TAR_EXCLUDES=()
for pat in "${EXCLUDES[@]}"; do
  [[ -n "$pat" ]] && TAR_EXCLUDES+=( --exclude="$pat" )
done

# Filenames
STAMP="$(ts_slug)"                                 # 2024-11-03-1430
BASE="backup-$STAMP"
ARCHIVE="$BACKUP_DESTINATION/$BASE.tar.gz"
CHECKSUM="$BACKUP_DESTINATION/$BASE.tar.gz.sha256"

# ------------------------------
# Lock (avoid concurrent runs)
# ------------------------------
exec 200>"$LOCK_FILE" || fail "Cannot open lock file $LOCK_FILE"
if ! flock -n 200; then
  fail "Another backup is running (lock present: $LOCK_FILE)"
fi
trap 'rm -f "$LOCK_FILE"' EXIT

# ------------------------------
# Functions
# ------------------------------
do_or_echo() {
  # Run command or just echo in dry-run
  if $DRY_RUN; then
    log "DRYRUN" "Would run: $*"
  else
    "$@"
  fi
}

create_backup() {
  log "INFO" "Starting backup of $SOURCE -> $ARCHIVE"
  if $DRY_RUN; then
    log "DRYRUN" "Would create archive: $ARCHIVE"
  else
    # -C to change to directory to handle spaces robustly, archive relative paths
    tar -czf "$ARCHIVE" -C "$SOURCE" "${TAR_EXCLUDES[@]}" .
    log "SUCCESS" "Backup created: $(basename "$ARCHIVE")"
  fi
}

write_checksum() {
  if $DRY_RUN; then
    log "DRYRUN" "Would write checksum: $CHECKSUM"
  else
    (cd "$BACKUP_DESTINATION" && sha256sum "$(basename "$ARCHIVE")" > "$(basename "$CHECKSUM")")
    log "INFO" "Checksum saved: $(basename "$CHECKSUM")"
  fi
}

verify_backup() {
  if $DRY_RUN; then
    log "DRYRUN" "Would verify checksum and test extraction for: $ARCHIVE"
    return
  fi

  # 1) Verify checksum
  (cd "$BACKUP_DESTINATION" && sha256sum -c "$(basename "$CHECKSUM")") \
    && log "INFO" "Checksum verified successfully" \
    || fail "Checksum verification FAILED"

  # 2) Try to list and extract a single entry as a test
  if ! tar -tzf "$ARCHIVE" >/dev/null; then
    fail "Archive listing FAILED"
  fi
  # Grab first path in archive
  local first
  first="$(tar -tzf "$ARCHIVE" | head -n 1 || true)"
  if [[ -z "$first" ]]; then
    fail "Archive seems empty"
  fi
  # Extract just that path to a temp dir
  local tmpdir
  tmpdir="$(mktemp -d)"
  if tar -xzf "$ARCHIVE" -C "$tmpdir" "$first"; then
    log "SUCCESS" "Backup verification SUCCESS"
    rm -rf "$tmpdir"
  else
    rm -rf "$tmpdir"
    fail "Test extraction FAILED"
  fi
}

# Helper: return the newest backup file (full path) on or before a given date (YYYY-MM-DD)
# Priority: same-day first; otherwise the most recent earlier one.
find_backup_for_date_or_before() {
  local target_date="$1"
  # List backups sorted newest first, filter by date <= target_date
  ls -1 "$BACKUP_DESTINATION"/backup-*.tar.gz 2>/dev/null | \
    awk -F'[/-]' -v d="$target_date" '
      {
        # name: backup-YYYY-MM-DD-HHMM.tar.gz
        # fields: 1:... 2:YYYY 3:MM 4:DD 5:HHMM.tar.gz
        y=$3; m=$4; dd=$5;
        filedate=sprintf("%s-%s-%s", y,m,dd);
        if (filedate <= d) print $0;
      }' | sort -r | head -n 1
}

# Helper: return the newest backup file inside a month (YYYY-MM)
find_backup_for_month() {
  local ym="$1"  # e.g., 2024-10
  ls -1 "$BACKUP_DESTINATION"/backup-*.tar.gz 2>/dev/null | \
    grep "backup-${ym}-" | sort -r | head -n 1 || true
}

# Calculate which backups to keep according to policy
# Result printed as full paths, one per line
compute_kept_set() {
  declare -A keep_map=()

  # === Daily: last N days (including today) ===
  for ((i=0; i<DAILY_KEEP; i++)); do
    d="$(date -d "-$i day" +%Y-%m-%d)"
    f="$(find_backup_for_date_or_before "$d" || true)"
    [[ -n "$f" ]] && keep_map["$f"]=1
  done

  # === Weekly: last N weeks (using last Sunday as anchor) ===
  # Find the last Sunday (including today if Sunday)
  last_sun="$(date -d "last sunday" +%Y-%m-%d 2>/dev/null || date -v-sun +%Y-%m-%d)"
  for ((w=0; w<WEEKLY_KEEP; w++)); do
    anchor="$(date -d "$last_sun -$w week" +%Y-%m-%d 2>/dev/null || date -v-"$((w))"w -v-sun +%Y-%m-%d)"
    f="$(find_backup_for_date_or_before "$anchor" || true)"
    [[ -n "$f" ]] && keep_map["$f"]=1
  done

  # === Monthly: first of each of last N months ===
  for ((m=0; m<MONTHLY_KEEP; m++)); do
    ym="$(date -d "-$m month" +%Y-%m 2>/dev/null || date -v-"$((m))"m +%Y-%m)"
    f="$(find_backup_for_month "$ym" || true)"
    if [[ -n "$f" ]]; then
      keep_map["$f"]=1
    else
      # fallback: any newest backup on/before the 1st of that month
      first_of_month="${ym}-01"
      fb="$(find_backup_for_date_or_before "$first_of_month" || true)"
      [[ -n "$fb" ]] && keep_map["$fb"]=1
    fi
  done

  # Print keys
  for k in "${!keep_map[@]}"; do echo "$k"; done
}

delete_old_backups() {
  # Build set to keep
  mapfile -t keep_list < <(compute_kept_set)
  declare -A keep=()
  for f in "${keep_list[@]:-}"; do keep["$f"]=1; done

  # Iterate all archives; delete if not in keep set
  mapfile -t all < <(ls -1 "$BACKUP_DESTINATION"/backup-*.tar.gz 2>/dev/null || true)
  for f in "${all[@]:-}"; do
    if [[ -z "${keep[$f]:-}" ]]; then
      # delete archive + its checksum if exists
      if $DRY_RUN; then
        log "DRYRUN" "Would delete old backup: $(basename "$f")"
        [[ -f "${f}.sha256" ]] && log "DRYRUN" "Would delete checksum: $(basename "${f}.sha256")"
      else
        rm -f -- "$f"
        log "INFO" "Deleted old backup: $(basename "$f")"
        [[ -f "${f}.sha256" ]] && { rm -f -- "${f}.sha256"; log "INFO" "Deleted checksum: $(basename "${f}.sha256")"; }
      fi
    fi
  done
}

# ------------------------------
# Main
# ------------------------------
log "INFO" "==== Run start (dry-run=$DRY_RUN) ===="

create_backup
write_checksum
verify_backup
delete_old_backups

log "INFO" "==== Run end ===="
