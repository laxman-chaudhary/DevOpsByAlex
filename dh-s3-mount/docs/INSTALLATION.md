# Installation / fleet rollout

1. Clone or distribute the `dh-s3-mount` repository to an Ubuntu/Debian system that boots with systemd.
2. Create an **untracked** `.env` from `.env.example`, or better provision a root-only `/etc/dh-s3-mount/config.env` outside Git.
3. Enter endpoint, bucket and access keys; for DataHub Nepal use `https://s3-np1.datahub.com.np`.
4. Before install, check `findmnt /mnt/s3-storage`. If a manual mount exists, finish uploads and unmount normally (`fusermount3 -u /mnt/s3-storage`).
5. Run `sudo ./install.sh`, then `sudo ./install.sh --status`.
6. Inspect `systemctl status dh-s3-mount.service` and `findmnt /mnt/s3-storage`.
7. Reboot only during a maintenance window, then rerun the verification.

The installer checks commands and installs missing `rclone`, `fuse3`, `util-linux`, and `psmisc` packages through apt. It does not try to install a different OS package manager.

## Existing deployments

Already have a working manual rclone mount? Stop it yourself before first install. Already have a custom systemd service? Keep using it or manually migrate: this utility refuses to overwrite unmanaged units.

## Rollout guidance

- Deploy first to a nonproduction test server.
- Use distinct least-privilege credentials per host, and separate prefixes/buckets by workload.
- Store secrets outside Git; restrict files to root (mode `0600`).
- Roll out in batches using Ansible or your preferred configuration-management system.
- Avoid rebooting production databases merely to test mounts; validate service startup directly first.
