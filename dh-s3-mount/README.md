# dh-s3-mount

Reusable, systemd-managed mount of one S3-compatible bucket per Ubuntu/Debian server, using rclone and FUSE **without a VFS disk file cache**.

## What it does

- Detects `rclone`, `fusermount3`, `findmnt`, and `fuser`, and installs missing packages (`rclone`, `fuse3`, `util-linux`, `psmisc`) with apt on Ubuntu/Debian.
- Validates S3 configuration and **lists the target bucket before changing an existing service**.
- Creates a root-only rclone credentials file under `/etc/dh-s3-mount/rclone.conf`.
- Creates, enables, and starts a systemd service (`dh-s3-mount.service` by default).
- Installs a daily `rclone cleanup` timer that aborts stale multipart uploads (invisible in listings, but billed), configurable or disabled per host.
- Ships `scripts/rclone-upload.sh`, a locked, retry-capable `rclone move` wrapper for multi-GB files that must not go through the mount.
- Uses `--vfs-cache-mode=off`; does not create a dedicated disk file-content cache.
- Supports `--status`, `--reconfigure`, and `--uninstall`, with optional credentials purge.
- Refuses to take over an unmanaged systemd unit or an existing manually mounted filesystem.

## Quick start

On EACH Ubuntu/Debian host:

```bash
cp .env.example .env
chmod 600 .env
sudoedit .env                  # Set your server-specific bucket and keys
sudo ./install.sh
sudo ./install.sh --status
```

Prefer storing secrets **outside the checkout**:

```bash
sudo install -d -m 700 /etc/dh-s3-mount
sudo install -m 600 .env.example /etc/dh-s3-mount/config.env
sudoedit /etc/dh-s3-mount/config.env
sudo ./install.sh --config /etc/dh-s3-mount/config.env
```

The default S3 endpoint is `https://s3-np1.datahub.com.np`; change it for other providers. The bucket name is mandatory. The default service name is `dh-s3-mount`, remote name `s3remote`, mount path `/mnt/s3-storage`.

**If your server already has a manual mount at the destination**, finish all transfers and unmount it yourself before running the installer. The installer will not forcibly take it over.

## Commands

```bash
sudo ./install.sh --install
sudo ./install.sh --status
sudo ./install.sh --reconfigure --config /path/to/updated.env
sudo ./install.sh --uninstall
sudo ./install.sh --uninstall --purge-config
```

- A repeat `--install` with an existing managed deployment is a no-op, not an implicit restart.
- Use `--reconfigure` when changing S3 keys or endpoint. It requires the same service name and mount path and a quiet mount; it may briefly interrupt access.
- `--uninstall` retains `/etc/dh-s3-mount/config.env` and `rclone.conf` so reinstallation is possible.
- `--purge-config` removes both of those files. Neither uninstall option deletes remote objects.

## Where files go

| Location | Purpose |
|---|---|
| `.env.example` | Committable configuration sample |
| `.env` | Optional local credentials; gitignored |
| `/etc/dh-s3-mount/config.env` | Persistent root-only settings |
| `/etc/dh-s3-mount/rclone.conf` | Generated root-only rclone credentials |
| `/etc/systemd/system/dh-s3-mount.service` | Generated systemd unit (name configurable) |
| `/etc/systemd/system/dh-s3-mount-cleanup.{service,timer}` | Generated multipart cleanup units, when enabled |
| `/mnt/s3-storage` | Default mounted bucket |
| `scripts/rclone-upload.sh` | Direct-to-S3 upload helper for multi-GB files |

## Verify

```bash
sudo ./install.sh --status
systemctl status dh-s3-mount.service
findmnt /mnt/s3-storage
ls -la /mnt/s3-storage
journalctl -u dh-s3-mount.service -n 50 --no-pager
```

### Known constraints

- **S3 is not a POSIX disk**: no reliable shared locking, atomic rename, or database data-directory semantics. Avoid using a mount for live PostgreSQL/MariaDB data.
- With VFS cache `off`, some file write patterns are unsupported and upload retries cannot be performed by the VFS. For backups, create a backup on local disk and upload directly with `rclone copy` or `aws s3 cp`.
- This installer tests bucket listing; credentials with only object-specific access may fail preflight.
- This installer handles **one bucket mount per host**. For multiple mounts on one host, extend service naming and per-instance state management before reuse.
- A root-owned mount is not automatically available to unprivileged users. `--allow-other` is intentionally not enabled.
- For fleets, roll out with Ansible, separate credentials per host, and use a secret manager or Ansible Vault.
- Never commit `.env`, credentials, or generated `rclone.conf` files to Git. Rotate any previously exposed keys.

More detail: [Installation](docs/INSTALLATION.md) · [Configuration](docs/CONFIGURATION.md) · [Troubleshooting](docs/TROUBLESHOOTING.md)

## Upstream references

- https://rclone.org/commands/rclone_mount/
- https://rclone.org/s3/


## Reliability notes (v1.1)

- The mount defaults to **no VFS file-content disk cache**. It is good for browsing and sequential access, but it is not a full POSIX filesystem. Applications that write `.part` files and rename them may fail or behave unexpectedly.
- `directory_markers = true` enables persistence of newly created empty S3 directories if supported by the storage provider.
- `--dir-cache-time=30s` refreshes external changes sooner (S3 usually does not provide rclone mount change polling). This increases listing requests. To force a refresh without restarting the service, run `systemctl kill -s HUP --kill-whom=main dh-s3-mount`, substituting your service name.
- Large files should be uploaded with **`rclone copy`/`move` directly**, not copied through the FUSE mount. `scripts/rclone-upload.sh` wraps this for cron use. See `docs/TROUBLESHOOTING.md` for the failure mode and examples.
- `--vfs-cache-mode=off` cannot retry an interrupted upload and cannot seek, so a multi-GB write that meets one transient error restarts from zero. This is a limitation of the mode, not of the bucket.
- Multipart uploads that are abandoned stay in the bucket invisibly and are billed. The installed `dh-s3-mount-cleanup.timer` aborts those older than 24 hours daily; a bucket lifecycle rule is the more reliable long-term fix.
- A stale FUSE mount must be diagnosed before detaching. The installer intentionally does not auto-run `fusermount3 -uz` because doing so could detach a live mount with pending I/O.
- Service restart rate limits prevent an endless aggressive restart loop when a stale mount remains.
- This release provides configuration and operational improvements, **not** automatic stale-mount recovery. Test on a staging server before rollout.
