# Configuration reference

All fields are placed in `.env` or root-only `/etc/dh-s3-mount/config.env`.
The parser accepts simple `KEY=VALUE` strings (plain or enclosed in a matching pair of quotes); it does **not** evaluate shell expressions, `${VAR}` substitutions, or `export KEY=...` syntax.

| Key | Example | Purpose |
|---|---|---|
| `S3_ENDPOINT` | `https://s3-np1.datahub.com.np` | HTTPS S3 API endpoint (hostname and optional port) |
| `S3_BUCKET` | `my-bucket` | Bucket to mount; required |
| `S3_ACCESS_KEY` | `REPLACE_ME` | Provider access key; required |
| `S3_SECRET_KEY` | `REPLACE_ME` | Provider secret key; required |
| `S3_REGION` | `""` | Empty for clones without a specified region |
| `S3_FORCE_PATH_STYLE` | `true` | S3 path-style addressing |
| `RCLONE_REMOTE` | `s3remote` | rclone remote name |
| `MOUNT_PATH` | `/mnt/s3-storage` | Absolute mount directory |
| `SERVICE_NAME` | `dh-s3-mount` | Generated systemd service basename |
| `CLEANUP_ENABLED` | `true` | Install the daily multipart-upload cleanup timer |
| `CLEANUP_TIME` | `03:00` | Zero-padded `HH:MM` (24-hour) daily run time for that timer |

Region and endpoint must match the provider's documentation. The sample uses an empty region and the S3-compatible `Other` provider, following the working DataHub setup. No canned ACL is applied by default.

**No VFS file-content cache:** The generated service includes `--vfs-cache-mode=off`. Rclone may still cache directory metadata in RAM, and normal OS buffering can occur; this setting is not a guarantee of zero memory usage.

**Uploads bypass the mount:** Because `off` mode cannot retry an interrupted write, multi-GB files must not be produced by writing into the mount. Use `scripts/rclone-upload.sh` (or `rclone move`/`copy` against the remote directly) for anything large; the mount is for browsing and small files. See [Troubleshooting](TROUBLESHOOTING.md#large-uploads-multi-gb-stall-or-fail-through-the-mount).

**Multipart cleanup:** with `CLEANUP_ENABLED=true` the installer also writes `${SERVICE_NAME}-cleanup.service` and `${SERVICE_NAME}-cleanup.timer`, which run `rclone cleanup` daily at `CLEANUP_TIME` to abort stale multipart uploads (older than 24 hours) that would otherwise be billed invisibly. Set it to `false` on hosts where a bucket lifecycle rule already handles this. The timer is independent of the mount service, so it survives mount outages.

Changes to credentials or endpoint: `sudo ./install.sh --reconfigure --config /path/to/updated.env`. An active mount may need to be disconnected to apply the change. Changing service name or mount path requires uninstall followed by reinstall.
