#!/usr/bin/env bash
# dh-s3-mount: provision a single S3-compatible rclone mount on Ubuntu/Debian.
# Run as root. Never writes to the remote bucket during installation.
set -Eeuo pipefail
umask 077

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR=/etc/dh-s3-mount
SAVED_CONFIG="$STATE_DIR/config.env"
RCLONE_CONFIG="$STATE_DIR/rclone.conf"
SYSTEMD_DIR=/etc/systemd/system
ACTION=install
CONFIG_SOURCE=""
PURGE_CONFIG=false
TMP_CONFIG=""
TMP_SERVICE=""
TMP_CLEANUP_SERVICE=""
TMP_CLEANUP_TIMER=""

log() { printf '[dh-s3-mount] %s\n' "$*"; }
fail() { printf '[dh-s3-mount] ERROR: %s\n' "$*" >&2; exit 1; }
cleanup() {
  local f
  for f in "$TMP_CONFIG" "$TMP_SERVICE" "$TMP_CLEANUP_SERVICE" "$TMP_CLEANUP_TIMER"; do
    [[ -z "$f" ]] || rm -f -- "$f"
  done
}
trap cleanup EXIT

usage() {
  cat <<'HELP'
Usage: sudo ./install.sh [action] [--config /path/to/config.env]
Actions:
  (none), --install   First install; no disruption if already installed
  --reconfigure      Apply settings changes (will restart an owned active mount)
  --status           Check service and mounted filesystem
  --uninstall        Stop, disable and remove service; keep credentials by default
  --uninstall --purge-config  Also remove managed credentials/config files
  -h, --help         Print this help

Use a root-owned config.env (chmod 600) or a local .env copied from .env.example.
This installer does not take ownership of existing non-managed systemd units/mounts.
HELP
}
while (($#)); do
  case "$1" in
    --install) ACTION=install ;;
    --reconfigure) ACTION=reconfigure ;;
    --status) ACTION=status ;;
    --uninstall) ACTION=uninstall ;;
    --purge-config) PURGE_CONFIG=true ;;
    --config) shift; (($#)) || fail '--config requires a path'; CONFIG_SOURCE="$1" ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown argument: $1" ;;
  esac
  shift
done
[[ "$EUID" -eq 0 ]] || fail 'Run this script as root (sudo).'
[[ "$PURGE_CONFIG" == false || "$ACTION" == uninstall ]] || fail '--purge-config is only valid with --uninstall'

# Read only whitelisted KEY=VALUE lines (never source or eval arbitrary config).
read_settings() {
  local src="$1" line key value
  [[ -f "$src" ]] || fail "Configuration not found: $src"
  S3_ENDPOINT='' S3_BUCKET='' S3_ACCESS_KEY='' S3_SECRET_KEY=''
  S3_REGION='' S3_FORCE_PATH_STYLE=true RCLONE_REMOTE=s3remote
  MOUNT_PATH=/mnt/s3-storage SERVICE_NAME=dh-s3-mount
  CLEANUP_ENABLED=true CLEANUP_TIME=03:00
  VFS_CACHE_MODE=full VFS_CACHE_DIR=/var/cache/dh-s3-mount
  VFS_CACHE_MAX_SIZE=20G VFS_CACHE_MAX_AGE=24h
  VFS_CACHE_ARGS=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
    [[ "$line" =~ ^[A-Z][A-Z0-9_]*= ]] || fail "Invalid config line in $src (expected KEY=VALUE)"
    key="${line%%=*}"; value="${line#*=}"
    # Support plain text or one pair of matching quotes; no shell expansion.
    if [[ "$value" == \"*\" && "${#value}" -ge 2 ]]; then value="${value:1:${#value}-2}";
    elif [[ "$value" == \'*\' && "${#value}" -ge 2 ]]; then value="${value:1:${#value}-2}"; fi
    case "$key" in
      S3_ENDPOINT) S3_ENDPOINT="$value" ;;
      S3_BUCKET) S3_BUCKET="$value" ;;
      S3_ACCESS_KEY) S3_ACCESS_KEY="$value" ;;
      S3_SECRET_KEY) S3_SECRET_KEY="$value" ;;
      S3_REGION) S3_REGION="$value" ;;
      S3_FORCE_PATH_STYLE) S3_FORCE_PATH_STYLE="$value" ;;
      RCLONE_REMOTE) RCLONE_REMOTE="$value" ;;
      MOUNT_PATH) MOUNT_PATH="$value" ;;
      SERVICE_NAME) SERVICE_NAME="$value" ;;
      CLEANUP_ENABLED) CLEANUP_ENABLED="$value" ;;
      CLEANUP_TIME) CLEANUP_TIME="$value" ;;
      VFS_CACHE_MODE) VFS_CACHE_MODE="$value" ;;
      VFS_CACHE_DIR) VFS_CACHE_DIR="$value" ;;
      VFS_CACHE_MAX_SIZE) VFS_CACHE_MAX_SIZE="$value" ;;
      VFS_CACHE_MAX_AGE) VFS_CACHE_MAX_AGE="$value" ;;
      *) fail "Unknown configuration key: $key" ;;
    esac
  done < "$src"
}

validate_settings() {
  [[ "$S3_ENDPOINT" =~ ^https://[A-Za-z0-9.-]+(:[0-9]{1,5})?/?$ ]] || fail 'S3_ENDPOINT must be an HTTPS endpoint with no path.'
  [[ "$S3_BUCKET" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ && "$S3_BUCKET" != *..* ]] || fail 'Invalid S3_BUCKET name.'
  [[ -n "$S3_ACCESS_KEY" && "$S3_ACCESS_KEY" != REPLACE_ME ]] || fail 'Set S3_ACCESS_KEY.'
  [[ -n "$S3_SECRET_KEY" && "$S3_SECRET_KEY" != REPLACE_ME ]] || fail 'Set S3_SECRET_KEY.'
  [[ "$RCLONE_REMOTE" =~ ^[A-Za-z][A-Za-z0-9_-]*$ ]] || fail 'Invalid RCLONE_REMOTE.'
  [[ "$SERVICE_NAME" =~ ^[A-Za-z][A-Za-z0-9_-]*$ ]] || fail 'Invalid SERVICE_NAME.'
  [[ "$MOUNT_PATH" =~ ^/[A-Za-z0-9_/-]+$ && "$MOUNT_PATH" != *..* && "$MOUNT_PATH" != / ]] || fail 'MOUNT_PATH must be a safe absolute directory (no spaces or ..).'
  [[ "$S3_REGION" =~ ^[A-Za-z0-9-]*$ ]] || fail 'Invalid S3_REGION.'
  [[ "$S3_FORCE_PATH_STYLE" == true || "$S3_FORCE_PATH_STYLE" == false ]] || fail 'S3_FORCE_PATH_STYLE must be true or false.'
  [[ "$CLEANUP_ENABLED" == true || "$CLEANUP_ENABLED" == false ]] || fail 'CLEANUP_ENABLED must be true or false.'
  [[ "$CLEANUP_TIME" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]] || fail 'CLEANUP_TIME must be HH:MM in 24-hour form.'
  # rclone has no "on"/"true" value for this flag; anything else aborts the mount.
  [[ "$VFS_CACHE_MODE" =~ ^(off|minimal|writes|full)$ ]] || fail 'VFS_CACHE_MODE must be one of: off, minimal, writes, full.'
  [[ "$VFS_CACHE_DIR" =~ ^/[A-Za-z0-9_/-]+$ && "$VFS_CACHE_DIR" != *..* && "$VFS_CACHE_DIR" != / ]] || fail 'VFS_CACHE_DIR must be a safe absolute directory (no spaces or ..).'
  [[ "$VFS_CACHE_MAX_SIZE" == off || "$VFS_CACHE_MAX_SIZE" =~ ^[0-9]+([kKmMgGtTpP]([iI]?[bB])?)?$ ]] || fail 'VFS_CACHE_MAX_SIZE must be a size such as 20G, 512M, or off.'
  [[ "$VFS_CACHE_MAX_AGE" == off || "$VFS_CACHE_MAX_AGE" =~ ^[0-9]+(s|m|h|d|w)$ ]] || fail 'VFS_CACHE_MAX_AGE must be a duration such as 24h, 30m, or off.'
}

# Build the VFS cache flags. `off` adds nothing at all, so a host that opts out
# keeps exactly the old command line. Kept as a function so tests can exercise
# it without a systemd host.
build_vfs_cache_args() {
  VFS_CACHE_ARGS=""
  [[ "$VFS_CACHE_MODE" == off ]] && return 0
  VFS_CACHE_ARGS=" --vfs-cache-mode=$VFS_CACHE_MODE --cache-dir=$VFS_CACHE_DIR"
  VFS_CACHE_ARGS+=" --vfs-cache-max-size=$VFS_CACHE_MAX_SIZE"
  VFS_CACHE_ARGS+=" --vfs-cache-max-age=$VFS_CACHE_MAX_AGE"
  return 0
}

# rclone size suffix -> KiB. Returns 0 for "off"/unparseable.
size_to_kib() {
  local s="$1" num unit mult
  [[ "$s" == off ]] && { printf '0\n'; return 0; }
  num="${s//[!0-9]/}"
  unit="${s##*[0-9]}"
  unit="${unit%%[iI]*}"
  unit="${unit%[bB]}"
  unit="$(printf '%s' "$unit" | tr '[:lower:]' '[:upper:]')"
  case "$unit" in
    ''|B) mult=1 ;;
    K) mult=1024 ;;
    M) mult=1048576 ;;
    G) mult=1073741824 ;;
    T) mult=1099511627776 ;;
    *) printf '0\n'; return 0 ;;
  esac
  printf '%s\n' "$((num * mult / 1024))"
}

# Expand literal placeholders; do not run shell evaluation on secrets.
render_template() {
  local input="$1" output="$2" line
  : > "$output"
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line//\{\{RCLONE_REMOTE\}\}/$RCLONE_REMOTE}"
    line="${line//\{\{S3_BUCKET\}\}/$S3_BUCKET}"
    line="${line//\{\{S3_ENDPOINT\}\}/$S3_ENDPOINT}"
    line="${line//\{\{S3_ACCESS_KEY\}\}/$S3_ACCESS_KEY}"
    line="${line//\{\{S3_SECRET_KEY\}\}/$S3_SECRET_KEY}"
    line="${line//\{\{S3_REGION\}\}/$S3_REGION}"
    line="${line//\{\{S3_FORCE_PATH_STYLE\}\}/$S3_FORCE_PATH_STYLE}"
    line="${line//\{\{SERVICE_NAME\}\}/$SERVICE_NAME}"
    line="${line//\{\{CLEANUP_TIME\}\}/$CLEANUP_TIME}"
    line="${line//\{\{VFS_CACHE_ARGS\}\}/$VFS_CACHE_ARGS}"
    line="${line//\{\{MOUNT_PATH\}\}/$MOUNT_PATH}"
    line="${line//\{\{RCLONE_BIN\}\}/$RCLONE_BIN}"
    line="${line//\{\{FUSERMOUNT_BIN\}\}/$FUSERMOUNT_BIN}"
    printf '%s\n' "$line" >> "$output"
  done < "$input"
}

ensure_dependencies() {
  local missing=() p
  for p in rclone fusermount3 findmnt fuser; do
    command -v "$p" >/dev/null 2>&1 || missing+=("$p")
  done
  if ((${#missing[@]})); then
    [[ -f /etc/os-release ]] || fail 'Cannot identify Linux distribution.'
    # shellcheck disable=SC1091
    . /etc/os-release
    [[ "${ID:-}" == ubuntu || "${ID:-}" == debian || " ${ID_LIKE:-} " == *' debian '* ]] || fail 'Automatic installation supports Ubuntu/Debian only.'
    command -v apt-get >/dev/null || fail 'apt-get is required.'
    log "Missing dependencies: ${missing[*]}; installing required packages via apt-get."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y --no-install-recommends rclone fuse3 util-linux psmisc
  fi
  for p in rclone fusermount3 findmnt fuser; do command -v "$p" >/dev/null || fail "Dependency still missing: $p"; done
  RCLONE_BIN="$(command -v rclone)"
  FUSERMOUNT_BIN="$(command -v fusermount3)"
  [[ "$RCLONE_BIN" == /* && "$FUSERMOUNT_BIN" == /* ]] || fail 'Required binaries must have absolute paths.'
}

managed_unit() {
  local unit="$1"
  [[ -f "$unit" ]] && grep -Fqx '# Managed by dh-s3-mount. Do not edit directly; run install.sh --reconfigure.' "$unit"
}

get_existing_service() {
  [[ -f "$STATE_DIR/service.name" ]] || return 1
  IFS= read -r EXISTING_SERVICE < "$STATE_DIR/service.name"
  [[ "$EXISTING_SERVICE" =~ ^[A-Za-z][A-Za-z0-9_-]*$ ]] || fail 'Invalid installed service metadata.'
}

check_mount_free() {
  local path="$1" source
  if findmnt -rn --mountpoint "$path" >/dev/null 2>&1; then
    source="$(findmnt -rn -o SOURCE --mountpoint "$path" || true)"
    fail "Mount point $path is already in use ($source). Stop/unmount it manually after completing transfers."
  fi
}

status() {
  local service path unit cache_mode cache_dir
  if ! get_existing_service; then log 'Not installed (no managed service metadata).'; return 1; fi
  service="$EXISTING_SERVICE"
  path="$(cat "$STATE_DIR/mount.path")"
  unit="$SYSTEMD_DIR/$service.service"
  printf 'Service: %s.service\nMount: %s\n' "$service" "$path"
  systemctl is-enabled "$service.service" || true
  systemctl is-active "$service.service" || true
  findmnt --mountpoint "$path" || true
  # Report the cache from the generated unit rather than from config.env, so the
  # output reflects what the running service was actually started with.
  cache_mode="$(grep -o -- '--vfs-cache-mode=[^ ]*' "$unit" 2>/dev/null | head -1 || true)"
  cache_dir="$(grep -o -- '--cache-dir=[^ ]*' "$unit" 2>/dev/null | head -1 || true)"
  if [[ -n "$cache_mode" ]]; then
    printf 'VFS cache: %s %s\n' "$cache_mode" "${cache_dir:-}"
    if [[ -n "$cache_dir" && -d "${cache_dir#--cache-dir=}" ]]; then
      printf 'Cache disk: '
      df -Ph "${cache_dir#--cache-dir=}" | awk 'NR==2 {print $4 " free of " $2 " on " $6}'
    fi
  else
    printf 'VFS cache: mode=off (no local file-content cache)\n'
  fi
  if [[ -f "$SYSTEMD_DIR/${service}-cleanup.timer" ]]; then
    printf 'Multipart cleanup timer: %s-cleanup.timer\n' "$service"
    systemctl is-enabled "${service}-cleanup.timer" || true
    systemctl is-active "${service}-cleanup.timer" || true
    systemctl list-timers --no-pager "${service}-cleanup.timer" 2>/dev/null || true
  else
    printf 'Multipart cleanup timer: not installed\n'
  fi
  systemctl is-active --quiet "$service.service" && findmnt -rn --mountpoint "$path" >/dev/null
}

uninstall() {
  local unit path svc cleanup_unit cleanup_timer
  if ! get_existing_service; then log 'No managed installation found; nothing to uninstall.'; return 0; fi
  svc="$EXISTING_SERVICE"; unit="$SYSTEMD_DIR/$svc.service"
  cleanup_unit="$SYSTEMD_DIR/${svc}-cleanup.service"
  cleanup_timer="$SYSTEMD_DIR/${svc}-cleanup.timer"
  managed_unit "$unit" || fail "Refusing to remove service not managed by this project: $unit"
  path="$(cat "$STATE_DIR/mount.path")"
  # The cleanup units never touch the mount, so they are stopped even when a
  # stuck mount would block the rest of the uninstall.
  systemctl disable --now "${svc}-cleanup.timer" >/dev/null 2>&1 || true
  log "Stopping $svc.service (complete all file operations first)."
  systemctl stop "$svc.service" || fail 'Service stop failed. Check open files; no files removed.'
  if findmnt -rn --mountpoint "$path" >/dev/null 2>&1; then fail "Still mounted at $path; refusing to remove the service."; fi
  systemctl disable "$svc.service" >/dev/null
  rm -f -- "$unit"
  if managed_unit "$cleanup_unit"; then rm -f -- "$cleanup_unit"; fi
  if managed_unit "$cleanup_timer"; then rm -f -- "$cleanup_timer"; fi
  systemctl daemon-reload
  if [[ -d "$path" ]]; then rmdir -- "$path" 2>/dev/null || true; fi
  if [[ "$PURGE_CONFIG" == true ]]; then
    rm -f -- "$STATE_DIR/config.env" "$STATE_DIR/rclone.conf" "$STATE_DIR/service.name" "$STATE_DIR/mount.path"
    rmdir -- "$STATE_DIR" 2>/dev/null || true
    log 'Removed managed configuration and credentials.'
  else
    rm -f -- "$STATE_DIR/service.name" "$STATE_DIR/mount.path"
    log "Retained credentials/config in $STATE_DIR (use --purge-config to delete)."
    log 'Local VFS cache contents were left in place and can be deleted manually.'
  fi
  log 'Uninstalled. No remote S3 objects were deleted.'
}

[[ "$(cat /proc/1/comm 2>/dev/null || true)" == systemd ]] || fail 'Requires systemd as PID 1.'
case "$ACTION" in
  status) status; exit $? ;;
  uninstall) uninstall; exit 0 ;;
esac

if [[ -z "$CONFIG_SOURCE" ]]; then
  if [[ -f "$SAVED_CONFIG" ]]; then CONFIG_SOURCE="$SAVED_CONFIG"
  else CONFIG_SOURCE="$PROJECT_DIR/.env"; fi
fi
read_settings "$CONFIG_SOURCE"
validate_settings
build_vfs_cache_args
if get_existing_service; then
  [[ "$EXISTING_SERVICE" == "$SERVICE_NAME" ]] || fail "Already installed as $EXISTING_SERVICE; uninstall it before changing SERVICE_NAME."
  if [[ "$ACTION" == install ]]; then
    log "Already installed as $SERVICE_NAME.service. Use --status or --reconfigure to apply changes."
    exit 0
  fi
else
  [[ "$ACTION" != reconfigure ]] || fail 'No managed installation found. Use --install first.'
fi

ensure_dependencies
install -d -m 700 "$STATE_DIR"
TMP_CONFIG="$(mktemp "$STATE_DIR/.rclone.XXXXXX")"
TMP_SERVICE="$(mktemp "$STATE_DIR/.service.XXXXXX")"
TMP_CLEANUP_SERVICE="$(mktemp "$STATE_DIR/.cleanup-service.XXXXXX")"
TMP_CLEANUP_TIMER="$(mktemp "$STATE_DIR/.cleanup-timer.XXXXXX")"
render_template "$PROJECT_DIR/config/rclone.conf.template" "$TMP_CONFIG"
render_template "$PROJECT_DIR/systemd/dh-s3-mount.service.template" "$TMP_SERVICE"
render_template "$PROJECT_DIR/systemd/dh-s3-mount-cleanup.service.template" "$TMP_CLEANUP_SERVICE"
render_template "$PROJECT_DIR/systemd/dh-s3-mount-cleanup.timer.template" "$TMP_CLEANUP_TIMER"
chmod 600 "$TMP_CONFIG" "$TMP_SERVICE" "$TMP_CLEANUP_SERVICE" "$TMP_CLEANUP_TIMER"

log "Checking S3 bucket access: $S3_BUCKET"
if ! "$RCLONE_BIN" --config "$TMP_CONFIG" lsf "$RCLONE_REMOTE:$S3_BUCKET" --max-depth 1 >/dev/null; then
  fail 'S3 preflight failed: check endpoint, bucket, region, credentials and ListBucket permission. Existing service untouched.'
fi
unit="$SYSTEMD_DIR/$SERVICE_NAME.service"
if [[ -f "$unit" ]] && ! managed_unit "$unit"; then fail "Unit exists and is not managed by this project: $unit"; fi
cleanup_unit="$SYSTEMD_DIR/${SERVICE_NAME}-cleanup.service"
cleanup_timer="$SYSTEMD_DIR/${SERVICE_NAME}-cleanup.timer"
for f in "$cleanup_unit" "$cleanup_timer"; do
  if [[ -f "$f" ]] && ! managed_unit "$f"; then fail "Unit exists and is not managed by this project: $f"; fi
done

if [[ "$ACTION" == install ]]; then
  check_mount_free "$MOUNT_PATH"
else
  oldpath="$(cat "$STATE_DIR/mount.path")"
  [[ "$oldpath" == "$MOUNT_PATH" ]] || fail 'MOUNT_PATH changes require uninstall/reinstall to avoid orphaned mounts.'
  log 'Reconfigure will stop the existing service. Ensure no processes have open files.'
  if findmnt -rn --mountpoint "$MOUNT_PATH" >/dev/null 2>&1 && fuser -m "$MOUNT_PATH" >/dev/null 2>&1; then
    fail 'Mount is currently in use. Stop users/transfers and retry --reconfigure.'
  fi
  systemctl stop "$SERVICE_NAME.service" || fail 'Could not stop old service; configuration unchanged.'
  check_mount_free "$MOUNT_PATH"
fi

[[ -d "$MOUNT_PATH" ]] || install -d -m 755 "$MOUNT_PATH"
# The cache is a bounded local staging area, not user data: create it root-only
# and warn when its ceiling would eat the filesystem it lives on.
if [[ "$VFS_CACHE_MODE" != off ]]; then
  install -d -m 700 "$VFS_CACHE_DIR"
  want_kib="$(size_to_kib "$VFS_CACHE_MAX_SIZE")"
  avail_kib="$(df -Pk "$VFS_CACHE_DIR" 2>/dev/null | awk 'NR==2 {print $4}')"
  if [[ "$want_kib" =~ ^[0-9]+$ && "$avail_kib" =~ ^[0-9]+$ ]] && ((want_kib > 0 && want_kib * 2 > avail_kib)); then
    log "WARNING: VFS_CACHE_MAX_SIZE=$VFS_CACHE_MAX_SIZE is more than half of the free space on $VFS_CACHE_DIR."
    log "WARNING: lower it or move VFS_CACHE_DIR to a larger filesystem before serving multi-GB writes."
  fi
fi
# Save the accepted, validated configuration and generated rclone credentials.
# Do not store plaintext credentials in the systemd unit.
if [[ "$(realpath -m -- "$CONFIG_SOURCE")" != "$SAVED_CONFIG" ]]; then
  install -m 600 "$CONFIG_SOURCE" "$SAVED_CONFIG"
else
  chmod 600 "$SAVED_CONFIG"
fi
install -m 600 "$TMP_CONFIG" "$RCLONE_CONFIG"
install -m 644 "$TMP_SERVICE" "$unit"
printf '%s\n' "$SERVICE_NAME" > "$STATE_DIR/service.name"
printf '%s\n' "$MOUNT_PATH" > "$STATE_DIR/mount.path"
chmod 600 "$STATE_DIR/service.name" "$STATE_DIR/mount.path"
# Multipart cleanup is installed as a separate timer so a failing clean up can
# never block the mount, and so it can be disabled per host.
if [[ "$CLEANUP_ENABLED" == true ]]; then
  install -m 644 "$TMP_CLEANUP_SERVICE" "$cleanup_unit"
  install -m 644 "$TMP_CLEANUP_TIMER" "$cleanup_timer"
else
  systemctl disable --now "${SERVICE_NAME}-cleanup.timer" >/dev/null 2>&1 || true
  rm -f -- "$cleanup_unit" "$cleanup_timer"
  log 'Multipart cleanup timer disabled (CLEANUP_ENABLED=false).'
fi
systemctl daemon-reload
systemctl enable "$SERVICE_NAME.service" >/dev/null
if [[ "$CLEANUP_ENABLED" == true ]]; then
  if systemctl enable --now "${SERVICE_NAME}-cleanup.timer" >/dev/null 2>&1; then
    log "Multipart cleanup timer enabled: ${SERVICE_NAME}-cleanup.timer at $CLEANUP_TIME daily."
  else
    log "WARNING: ${SERVICE_NAME}-cleanup.timer could not be enabled; check systemctl status."
  fi
fi
if ! systemctl start "$SERVICE_NAME.service"; then
  log "Service failed to start; inspect: journalctl -u $SERVICE_NAME.service -n 80 --no-pager"
  fail 'Service start failed.'
fi
systemctl is-active --quiet "$SERVICE_NAME.service" || fail 'Service not active after start.'
findmnt -rn --mountpoint "$MOUNT_PATH" >/dev/null || fail 'Service active but mount point not visible.'
log "SUCCESS: $RCLONE_REMOTE:$S3_BUCKET mounted at $MOUNT_PATH"
log "Auto-start enabled: $SERVICE_NAME.service"
log "Status: sudo ./install.sh --status"
