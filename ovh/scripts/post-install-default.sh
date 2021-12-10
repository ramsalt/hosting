#!/usr/bin/env bash

set -e
set -o pipefail
set -o nounset

if [[ "-" != "${DEBUG:-}" ]]; then
  set -x
fi

MOUNTPOINT=/mnt/data

# Ensure the mount directory is empty!
if [[ $(find $MOUNTPOINT -type f | wc -l) -gt 0 ]]; then
  echo "[ERROR] Mount directory '$MOUNTPOINT' is not empty!" 1>&2
  exit 1
fi

# Ensure that we can detect the device.
DEV_NAME="$(mount -l | grep "$MOUNTPOINT" | cut -d' ' -f1)"
if [[ -z "$DEV_NAME" ]]; then
  echo "[ERROR] Could not find the device for mount '$MOUNTPOINT'." 1>&2
  exit 2
fi

# Store the old UUID to replace it in fstab.
OLD_UUID=$(blkid -o value -s UUID $DEV_NAME)

# Reformat the partition with increased i-node count.
umount "$MOUNTPOINT"
mkfs.ext4 -F -i 2048 $DEV_NAME

NEW_UUID=$(blkid -o value -s UUID $DEV_NAME)
sed --in-place -e "s/$OLD_UUID/$NEW_UUID/" /etc/fstab

# Reload config and re-mount the disk.
systemctl daemon-reload 
mount -a

# Check if mountpoint is re-mounted.
if [[ -z "$(mount  -l | grep $MOUNTPOINT )" ]]; then
  echo "[ERROR] Re-mount error: '$MOUNTPOINT' did not auto-mount." 1>&2
  exit 3
fi

# Create symlinks for docker and wodby.
mkdir "$MOUNTPOINT/var-lib-docker" "$MOUNTPOINT/srv-wodby"
ln -s "$MOUNTPOINT/var-lib-docker" /var/lib/docker
ln -s "$MOUNTPOINT/srv-wodby" /srv/wodby

# All done.