#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")/.."
bash -n install.sh
./install.sh --help >/dev/null 2>&1 || true  # --help root check occurs after parsing; no changes
[[ -f .env.example && -f .gitignore ]]
! grep -q 'YOUR_ACTUAL_SECRET' .env.example
[[ "$(grep -c '^ExecStart=' systemd/dh-s3-mount.service.template)" -eq 1 ]]
printf 'Static checks passed.\n'
