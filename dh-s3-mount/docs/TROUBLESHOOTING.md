# Troubleshooting

## AccessDenied when listing root

`rclone lsd remote:` lists **all buckets** and can fail with 403 when credentials only allow access to one bucket. The installer tests `remote:bucket` explicitly.

## AccessDenied on the target bucket

Confirm bucket spelling, endpoint, region, access key and secret, and `ListBucket` permission:

```bash
sudo rclone --config /etc/dh-s3-mount/rclone.conf lsf s3remote:YOUR_BUCKET --max-depth 1
```

Do not paste secrets or a full `rclone.conf` into support chats.

## Installation refuses an existing mount

Check `findmnt /mnt/s3-storage` and complete any in-progress transfers. If the mount is from a separate manual rclone process, unmount it gracefully before installing this managed unit. No forced/lazy unmount is performed.

## Service does not start

```bash
systemctl status dh-s3-mount.service
journalctl -u dh-s3-mount.service -n 100 --no-pager
command -v rclone fusermount3
```

Check mount permissions, DNS/network connectivity, provider availability and that systemd is PID 1. If a network-online dependency is not functioning on your OS, configure the matching wait-online implementation.

## Status shows active but no mount

Run `findmnt /mnt/s3-storage`, inspect logs and check for an unrelated filesystem on the path. Report the discrepancy rather than repeatedly forcing unmounts.

## Reconfigure says busy

Close shells, applications, backup jobs and any files open on the mount. Do not delete or forcibly unmount files still being uploaded.

## Uninstall safety

`--uninstall` stops/removes only the project's marked service, and leaves remote bucket contents intact. It retains credentials by default. `--uninstall --purge-config` also removes locally managed secrets and settings.


## Stale FUSE mount / `d?????????` / directory already mounted

This typically means that the kernel mount exists but its userspace filesystem process is no longer responding. Diagnose before changing anything:

```bash
systemctl status dh-s3-mount --no-pager
findmnt -rn -o TARGET,SOURCE,FSTYPE /mnt/s3-storage
pgrep -af 'rclone mount'
journalctl -u dh-s3-mount -n 100 --no-pager
```

If active transfers exist, do not unmount. Once you have confirmed the mount is stale and no processes are using it:

```bash
systemctl stop dh-s3-mount
fusermount3 -u /mnt/s3-storage
```

If normal unmount is impossible, `fusermount3 -uz /mnt/s3-storage` is a **last resort** for a confirmed dead mount. It can disconnect open handles and cannot guarantee upload completion. Then:

```bash
findmnt /mnt/s3-storage
systemctl reset-failed dh-s3-mount
systemctl start dh-s3-mount
```

Do not add `--allow-non-empty` or an unconditional lazy unmount to the service.

## External directory changes / empty directories

Rclone directory listing caches are distinct from VFS disk file caches. The service now sets `--dir-cache-time=30s --poll-interval=0` to refresh cross-server changes faster. `directory_markers = true` persists newly created empty folders as zero-byte S3 marker objects if supported. Changes may still take up to the configured directory cache duration to become visible.

To flush in-memory directory listings:

```bash
systemctl kill -s HUP --kill-whom=main dh-s3-mount
```

## Large backups and multipart uploads

For large files, bypass the mount and use rclone's retry-capable copy. For example:

```bash
rclone copy /backups/large-backup.tar.gz s3remote:YOUR_BUCKET_NAME/backups/ \
  --config=/etc/dh-s3-mount/rclone.conf \
  --s3-chunk-size=16Mi --s3-upload-concurrency=2 --transfers=1 \
  --retries=5 --low-level-retries=10 --timeout=10m --progress
```

Check multipart permissions and the service logs if uploads still fail. `.part` files may be created by the originating application and can indicate a rename-based writing workflow, which is problematic on no-cache S3 mounts.

Rclone reference: https://rclone.org/commands/rclone_mount/ and https://rclone.org/s3/
