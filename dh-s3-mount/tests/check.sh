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

# 5. VFS cache mode stays documented as off; Option A is the supported path for
#    multi-GB uploads, so an accidental switch to a disk cache must be explicit.
grep -q -- '--vfs-cache-mode=off' systemd/dh-s3-mount.service.template || fail 'mount template lost --vfs-cache-mode=off'

printf 'Static checks passed.\n'
