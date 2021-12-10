#!/usr/bin/env bash

set -e
set -o pipefail
set -o nounset

if [[ "-" != "${DEBUG:-}" ]]; then
  set -x
fi

main() {
  setup_data_partition
}

setup_data_partition() {
  local data_mount=/mnt/data

  # Ensure the mount directory is empty!
  if [[ $(find "$data_mount" -type f | wc -l) -gt 0 ]]; then
    echo "[ERROR] Mount directory '${data_mount}' is not empty!" 1>&2
    exit 1
  fi

  # Ensure that we can detect the device.
  local block_dev_name=$(mount -l | grep "${data_mount}" | cut -d' ' -f1)
  if [[ -z "$block_dev_name" ]]; then
    echo "[ERROR] Could not find the device for mount '${data_mount}'." 1>&2
    exit 2
  fi

  # Store the old UUID to replace it in fstab.
  local old_dev_uuid=$(blkid -o value -s UUID "${block_dev_name}")

  # Reformat the partition with increased i-node count.
  umount "${data_mount}"
  mkfs.ext4 -F -i 2048 "${block_dev_name}"

  local new_dev_uuid=$(blkid -o value -s UUID "${block_dev_name}")
  sed --in-place -e "s/${old_dev_uuid}/${new_dev_uuid}/" /etc/fstab

  # Reload config and re-mount the disk.
  systemctl daemon-reload 
  mount -a

  # Check if data_mount is re-mounted.
  if [[ -z "$(mount  -l | grep $data_mount )" ]]; then
    echo "[ERROR] Re-mount error: '${data_mount}' did not auto-mount." 1>&2
    exit 3
  fi

  # Create symlinks for docker and wodby.
  mkdir "${data_mount}/var-lib-docker" "${data_mount}/srv-wodby"
  ln -s "${data_mount}/var-lib-docker" /var/lib/docker
  ln -s "${data_mount}/srv-wodby" /srv/wodby
  # All done.
}


#
# Actual script: main function
#
main