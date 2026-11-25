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

Region and endpoint must match the provider's documentation. The sample uses an empty region and the S3-compatible `Other` provider, following the working DataHub setup. No canned ACL is applied by default.

**No VFS file-content cache:** The generated service includes `--vfs-cache-mode=off`. Rclone may still cache directory metadata in RAM, and normal OS buffering can occur; this setting is not a guarantee of zero memory usage.

Changes to credentials or endpoint: `sudo ./install.sh --reconfigure --config /path/to/updated.env`. An active mount may need to be disconnected to apply the change. Changing service name or mount path requires uninstall followed by reinstall.
