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

## Large uploads (multi-GB) stall or fail through the mount

Symptom: `rsync`, `cp` or an application writing into `/mnt/s3-storage` handles small
files fine, but a multi-GB file fails near the end (`Input/output error`, a broken
pipe, or a silent disappearance), and the cron job simply retries the whole file
forever.

The generated unit runs `--vfs-cache-mode=off`, which rclone documents as unable to
retry a failed upload and unable to seek in a file opened for write. A single
transient `5xx`, timeout or dropped connection mid-transfer therefore discards
everything already streamed, and nothing local survives to resume from.

Do not fix this by pointing rsync at the mount with a bigger block size: rsync only
sees a FUSE filesystem and cannot drive S3 multipart semantics.

### Recommended: bypass the mount

`scripts/rclone-upload.sh` drives `rclone move` against the native S3 backend. Files
above `--s3-upload-cutoff` (200 Mi by default) upload as multipart, each part is
retried, and the local file is deleted only after the remote copy is verified.

```bash
# One-off
sudo /usr/local/bin/rclone-upload.sh \
  --log-file /var/log/rclone-upload.log \
  /root/.qbit/downloads/ s3remote:YOUR_BUCKET/media/Latest/

# Cron, replacing the rsync line
*/5 * * * * /usr/local/bin/rclone-upload.sh \
  --log-file /var/log/rclone-upload.log \
  /root/.qbit/downloads/ s3remote:YOUR_BUCKET/media/Latest/
```

The script refuses to run if the source is inside the managed mount, takes a lock
so overlapping cron runs skip instead of racing, prunes now-empty source
directories (`--delete-empty-src-dirs`), and defaults to 64 Mi chunks with 4
concurrent part uploads (`DH_S3_MOUNT_CHUNK_SIZE`, `DH_S3_MOUNT_UPLOAD_CONCURRENCY`,
`DH_S3_MOUNT_TRANSFERS` override them). `--dry-run` shows what would move.

Avoid `--skip-existing` in a recurring job: with `move`, files already present on the
remote are left in the source directory and nothing prunes them.

### Manual equivalent

```bash
rclone move /data/staging/ s3remote:YOUR_BUCKET/backups/ \
  --config=/etc/dh-s3-mount/rclone.conf \
  --s3-chunk-size=64Mi --s3-upload-concurrency=4 \
  --transfers=2 --checkers=4 \
  --retries=5 --low-level-retries=10 \
  --delete-empty-src-dirs --log-file=/var/log/rclone-upload.log --log-level=INFO
```

### If other services must keep writing through the mount

The mount cannot be made resumable, but buffering to local disk lets rclone start a
real multipart upload on close and retry failed parts. That requires a bounded
cache, otherwise a multi-GB download can fill the root filesystem:

```ini
--vfs-cache-mode=writes --vfs-cache-max-size=20G --vfs-cache-max-age=24h
--s3-chunk-size=64Mi --s3-upload-concurrency=4
```

In `writes` mode the upload starts only when the writer closes the file, so an
interrupted producer still restarts from zero. Prefer the direct upload above.
This project's unit is generated: change the template or add the keys to the
service via `install.sh`, never by editing `/etc/systemd/system/dh-s3-mount.service`
by hand, or `--reconfigure` will overwrite it.

## Orphaned multipart uploads

An aborted large upload leaves parts in the bucket that never appear in `ls` or
`rclone ls` but are still billed. Inspect them with:

```bash
sudo rclone backend list-multipart-uploads s3remote:YOUR_BUCKET \
  --config=/etc/dh-s3-mount/rclone.conf
```

The installer enables a daily timer (`dh-s3-mount-cleanup.timer`, 03:00 by default)
that runs `rclone cleanup`, which aborts pending uploads older than 24 hours. Check
or trigger it with:

```bash
systemctl list-timers 'dh-s3-mount-cleanup*'
sudo systemctl start dh-s3-mount-cleanup.service
sudo journalctl -u dh-s3-mount-cleanup.service -n 50 --no-pager
```

For a different age threshold use the backend command directly, e.g.
`rclone backend cleanup s3remote:YOUR_BUCKET -o max-age=1h`. A bucket lifecycle rule
(`AbortIncompleteMultipartUpload`) is the most reliable option because it applies
regardless of which host or tool started the upload.

If the cleanup service fails with `AccessDenied`, the credentials lack
`s3:ListBucketMultipartUploads` and `s3:AbortMultipartUpload`. Either grant those for
the bucket or set `CLEANUP_ENABLED="false"` and rely on a lifecycle rule.

Rclone reference: https://rclone.org/commands/rclone_mount/ and https://rclone.org/s3/
