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
| `VFS_CACHE_MODE` | `full` | `off` \| `minimal` \| `writes` \| `full`; there is no `on`/`true` value |
| `VFS_CACHE_DIR` | `/var/cache/dh-s3-mount` | Root-only cache directory, created by the installer |
| `VFS_CACHE_MAX_SIZE` | `20G` | Ceiling for cached file content, or `off` for unlimited |
| `VFS_CACHE_MAX_AGE` | `24h` | Evict objects not accessed within this window, or `off` |
| `CLEANUP_ENABLED` | `true` | Install the daily multipart-upload cleanup timer |
| `CLEANUP_TIME` | `03:00` | Zero-padded `HH:MM` (24-hour) daily run time for that timer |

Region and endpoint must match the provider's documentation. The sample uses an empty region and the S3-compatible `Other` provider, following the working DataHub setup. No canned ACL is applied by default.

**VFS cache:** The generated service defaults to `--vfs-cache-mode=full --cache-dir=/var/cache/dh-s3-mount --vfs-cache-max-size=20G --vfs-cache-max-age=24h`.

- `full` buffers reads and writes on local disk. Writes become seekable and a failed upload can be retried, which `off` cannot do.
- `VFS_CACHE_MAX_SIZE` is a real disk-space boundary on the filesystem holding `VFS_CACHE_DIR`. The installer warns when it exceeds half the free space; it does not silently shrink it.
- `off` omits every cache flag and restores the previous no-cache command line exactly, so a host can opt out with `VFS_CACHE_MODE="off"`.
- Directory metadata is still cached in RAM regardless of mode, and the VFS cache is not a guarantee of zero memory use.
- Cache contents are derived data, not authoritative state: they can be deleted while the mount is stopped, at the cost of re-downloading.

**Bulk uploads still bypass the mount.** A cache makes mount writes retryable, but the upload only starts when the writer closes the file and the bytes occupy cache until then. For scheduled or bulk transfers use `scripts/rclone-upload.sh` (or `rclone move`/`copy` against the remote directly); it is cheaper in disk and easier to reason about. See [Troubleshooting](TROUBLESHOOTING.md#large-uploads-multi-gb-stall-or-fail-through-the-mount).

**Multipart cleanup:** with `CLEANUP_ENABLED=true` the installer also writes `${SERVICE_NAME}-cleanup.service` and `${SERVICE_NAME}-cleanup.timer`, which run `rclone cleanup` daily at `CLEANUP_TIME` to abort stale multipart uploads (older than 24 hours) that would otherwise be billed invisibly. Set it to `false` on hosts where a bucket lifecycle rule already handles this. The timer is independent of the mount service, so it survives mount outages.

Changes to credentials or endpoint: `sudo ./install.sh --reconfigure --config /path/to/updated.env`. An active mount may need to be disconnected to apply the change. Changing service name or mount path requires uninstall followed by reinstall.
