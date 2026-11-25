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
