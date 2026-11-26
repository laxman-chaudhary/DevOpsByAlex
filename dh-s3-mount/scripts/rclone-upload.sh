#!/usr/bin/env bash
# dh-s3-mount: move a local directory into the bucket via the native S3 backend.
#
# Why this exists: the managed mount runs with --vfs-cache-mode=off. In that
# mode rclone streams writes straight through, cannot seek, and cannot retry a
# failed upload (rclone mount(1), "VFS File Caching"). A multi-GB file that hits
# one transient error near the end is discarded and restarted from byte zero.
# This wrapper bypasses FUSE: rclone move talks to the S3 API directly, streams
# each file above --s3-upload-cutoff as a retryable multipart upload, and
# removes the local file only after the remote copy is verified.
#
# Usage:
#   rclone-upload.sh [options] <source-dir> <remote:path>
#
# Cron example (replaces rsync against /mnt/s3-storage):
#   */5 * * * * /usr/local/bin/rclone-upload.sh \
#       --log-file /var/log/rclone-upload.log \
#       /root/.qbit/downloads/ s3remote:lexcorp/media/Latest/
set -Eeuo pipefail
umask 077

PROG=${0##*/}
STATE_DIR=/etc/dh-s3-mount
CONFIG=${DH_S3_MOUNT_CONFIG:-$STATE_DIR/rclone.conf}
LOCK_FILE=/run/dh-s3-mount-upload.lock
LOG_FILE=""
DRY_RUN=false
SKIP_EXISTING=false
KEEP_EMPTY_DIRS=false

# Tunables. Override per host with the matching environment variable.
CHUNK_SIZE=${DH_S3_MOUNT_CHUNK_SIZE:-64Mi}
UPLOAD_CONCURRENCY=${DH_S3_MOUNT_UPLOAD_CONCURRENCY:-4}
TRANSFERS=${DH_S3_MOUNT_TRANSFERS:-2}
CHECKERS=${DH_S3_MOUNT_CHECKERS:-4}
RETRIES=${DH_S3_MOUNT_RETRIES:-5}
LOW_LEVEL_RETRIES=${DH_S3_MOUNT_LOW_LEVEL_RETRIES:-10}
LOG_LEVEL=${DH_S3_MOUNT_LOG_LEVEL:-INFO}

log() { printf '%s: %s\n' "$PROG" "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

usage() {
  cat <<'HELP'
Usage: rclone-upload.sh [options] <source-dir> <remote:path>

Moves every file under <source-dir> to <remote:path> using rclone's native S3
backend, bypassing the FUSE mount. Source files are deleted only after a
successful, verified upload.

Options:
  --config PATH        rclone credentials file (default /etc/dh-s3-mount/rclone.conf)
  --log-file PATH      Append rclone's log to PATH (recommended for cron)
  --dry-run            Show what would be transferred; change nothing
  --skip-existing      Pass --ignore-existing (see caveat below)
  --keep-empty-dirs    Do not prune now-empty source directories
  -h, --help           Print this help

Environment tunables:
  DH_S3_MOUNT_CHUNK_SIZE (64Mi), DH_S3_MOUNT_UPLOAD_CONCURRENCY (4),
  DH_S3_MOUNT_TRANSFERS (2), DH_S3_MOUNT_CHECKERS (4), DH_S3_MOUNT_RETRIES (5),
  DH_S3_MOUNT_LOW_LEVEL_RETRIES (10), DH_S3_MOUNT_LOG_LEVEL (INFO)

Caveat: --skip-existing keeps files that already exist on the remote in the
source directory indefinitely. Only use it when something else prunes them.
HELP
}

while (($#)); do
  case "$1" in
    --config) shift; (($#)) || die '--config requires a path'; CONFIG="$1" ;;
    --log-file) shift; (($#)) || die '--log-file requires a path'; LOG_FILE="$1" ;;
    --dry-run) DRY_RUN=true ;;
    --skip-existing) SKIP_EXISTING=true ;;
    --keep-empty-dirs) KEEP_EMPTY_DIRS=true ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    -*) die "unknown option: $1 (see --help)" ;;
    *) break ;;
  esac
  shift
done
(($# == 2)) || { usage >&2; exit 2; }
SOURCE=$1
DEST=$2

command -v rclone >/dev/null 2>&1 || die 'rclone not found in PATH.'
[[ -f "$CONFIG" ]] || die "rclone config not found: $CONFIG (run install.sh first)"
[[ -d "$SOURCE" ]] || die "source is not a directory: $SOURCE"

# The destination must be a remote:path, never a local path. Without a colon in
# the first path element a user could accidentally point at the FUSE mount and
# reintroduce exactly the failure this script exists to avoid.
[[ "$DEST" == *:* ]] || die "destination must be remote:path (got '$DEST')"
[[ "${DEST%%:*}" =~ ^[A-Za-z][A-Za-z0-9_-]*$ ]] || die "invalid remote name in '$DEST'"

# Never recurse into the managed mount: moving from the mount back into the
# bucket double-transfers through FUSE and can deadlock the VFS.
if [[ -f "$STATE_DIR/mount.path" ]]; then
  mount_path=$(cat "$STATE_DIR/mount.path" 2>/dev/null || true)
  if [[ -n "$mount_path" ]]; then
    src_abs=$(realpath -m -- "$SOURCE")
    if [[ "$src_abs" == "$mount_path" || "$src_abs" == "$mount_path"/* ]]; then
      die "source is inside the managed mount ($mount_path); pass the local staging directory instead."
    fi
  fi
fi

# One transfer at a time. Overlapping cron runs on a huge file waste bandwidth
# and can trip provider rate limits, so skip instead of queueing.
if command -v flock >/dev/null 2>&1; then
  exec 9>"$LOCK_FILE" || die "cannot open lock file: $LOCK_FILE"
  flock -n 9 || { log 'another upload is already running; skipping this cycle.'; exit 75; }
fi

cmd=(
  rclone move "$SOURCE" "$DEST"
  --config "$CONFIG"
  --s3-chunk-size "$CHUNK_SIZE"
  --s3-upload-concurrency "$UPLOAD_CONCURRENCY"
  --transfers "$TRANSFERS"
  --checkers "$CHECKERS"
  --retries "$RETRIES"
  --low-level-retries "$LOW_LEVEL_RETRIES"
  --log-level "$LOG_LEVEL"
  --stats 1m
)
[[ -n "$LOG_FILE" ]] && cmd+=(--log-file "$LOG_FILE")
[[ "$DRY_RUN" == true ]] && cmd+=(--dry-run)
[[ "$SKIP_EXISTING" == true ]] && cmd+=(--ignore-existing)
[[ "$KEEP_EMPTY_DIRS" == false ]] && cmd+=(--delete-empty-src-dirs)

rc=0
"${cmd[@]}" || rc=$?
if ((rc != 0)); then
  log "rclone move failed with exit code $rc; source files were not removed for failed transfers."
  [[ -n "$LOG_FILE" ]] && log "recent log: tail -n 50 $LOG_FILE"
fi
exit "$rc"
