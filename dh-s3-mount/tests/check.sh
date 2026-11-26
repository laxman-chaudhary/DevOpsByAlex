#!/usr/bin/env bash
# Static checks only: no root, no network, no systemd mutations.
set -Eeuo pipefail
cd "$(dirname "$0")/.."

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# 1. Shell syntax of every shipped script.
for f in install.sh scripts/*.sh tests/check.sh; do bash -n "$f" || fail "syntax error in $f"; done

./install.sh --help >/dev/null 2>&1 || true  # --help root check occurs after parsing; no changes

[[ -f .env.example && -f .gitignore ]] || fail 'missing .env.example or .gitignore'
! grep -q 'YOUR_ACTUAL_SECRET' .env.example || fail '.env.example contains a placeholder secret'
[[ "$(grep -c '^ExecStart=' systemd/dh-s3-mount.service.template)" -eq 1 ]] || fail 'service template must have exactly one ExecStart'

# 2. Every {{PLACEHOLDER}} used by a template must be expanded by render_template.
#    An unexpanded token ships a literal "{{FOO}}" into a systemd unit.
#    render_template escapes braces, so unescape install.sh before comparing.
sed 's/\\{/{/g; s/\\}/}/g' install.sh > /tmp/dh-s3-mount-install-unescaped.$$
trap 'rm -f /tmp/dh-s3-mount-install-unescaped.$$' EXIT
for tpl in systemd/*.template config/*.template; do
  while IFS= read -r ph; do
    [[ -n "$ph" ]] || continue
    grep -Fq "$ph" /tmp/dh-s3-mount-install-unescaped.$$ || fail "$tpl uses $ph but render_template never substitutes it"
  done < <(grep -o '{{[A-Z_]*}}' "$tpl" | sort -u)
done

# 3. Upload helper must bypass FUSE and use a large-file friendly chunk size.
upload=scripts/rclone-upload.sh
[[ -x "$upload" ]] || fail "$upload is not executable"
grep -q 'rclone move' "$upload" || fail "$upload must use rclone move (native backend)"
grep -q -- '--s3-chunk-size' "$upload" || fail "$upload must set --s3-chunk-size"
! grep -Eq -- 'rclone (copy|move|sync) [^ ]*/mnt/' "$upload" || fail "$upload must not target the mount path"

# 4. Cleanup timer wiring.
grep -q '^OnCalendar=' systemd/dh-s3-mount-cleanup.timer.template || fail 'cleanup timer has no OnCalendar'
grep -q '^Unit={{SERVICE_NAME}}-cleanup.service$' systemd/dh-s3-mount-cleanup.timer.template || fail 'cleanup timer Unit= mismatch'
grep -Fq '{{RCLONE_BIN}} cleanup' systemd/dh-s3-mount-cleanup.service.template || fail 'cleanup service does not call rclone cleanup'
grep -q 'CLEANUP_ENABLED' install.sh || fail 'install.sh does not handle CLEANUP_ENABLED'
grep -q 'CLEANUP_TIME' install.sh || fail 'install.sh does not handle CLEANUP_TIME'

# 5. VFS cache mode is a validated knob, not a literal flag: rclone aborts on an
#    unknown value (there is no "on"/"true"), which would leave the mount dead.
grep -q '{{VFS_CACHE_ARGS}}' systemd/dh-s3-mount.service.template || fail 'service template must inject {{VFS_CACHE_ARGS}}'
grep -q 'VFS_CACHE_MODE must be one of' install.sh || fail 'VFS_CACHE_MODE is not validated'

# Exercise the real builders from install.sh so the emitted flags cannot drift.
eval "$(sed -n '/^build_vfs_cache_args()/,/^}/p' install.sh)"
eval "$(sed -n '/^size_to_kib()/,/^}/p' install.sh)"

VFS_CACHE_MODE=off build_vfs_cache_args
[[ -z "$VFS_CACHE_ARGS" ]] || fail 'VFS_CACHE_MODE=off must not add any cache flag'

VFS_CACHE_MODE=full VFS_CACHE_DIR=/var/cache/dh-s3-mount \
  VFS_CACHE_MAX_SIZE=20G VFS_CACHE_MAX_AGE=24h build_vfs_cache_args
for want in '--vfs-cache-mode=full' '--cache-dir=/var/cache/dh-s3-mount' \
            '--vfs-cache-max-size=20G' '--vfs-cache-max-age=24h'; do
  [[ "$VFS_CACHE_ARGS" == *"$want"* ]] || fail "cache args are missing $want"
done

[[ "$(size_to_kib 20G)" -eq $((20 * 1024 * 1024)) ]] || fail 'size_to_kib is wrong for 20G'
[[ "$(size_to_kib 512M)" -eq 524288 ]] || fail 'size_to_kib is wrong for 512M'
[[ "$(size_to_kib off)" -eq 0 ]] || fail 'size_to_kib is wrong for off'

printf 'Static checks passed.\n'
