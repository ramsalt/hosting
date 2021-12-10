#!/usr/bin/env bash

set -e
set -o pipefail
set -o nounset

if [[ "-" != "${DEBUG:-}" ]]; then
  set -x
fi

# Code for error "Missing prerequisite"
readonly ERR_PRE_REQ=1
# Code for "Runtime error"
readonly ERR_RUNTIME=2


main() {
  check_distro
  do_upgrade
  setup_data_partition
}


error() {
  cat <<< "${0##*/}: $@" 1>&2;
}


check_distro () {
  if ! [[ -r '/etc/os-release' ]]; then
    error "Missing OS Release file!"
    exit $ERR_PRE_REQ
  fi
  local distro=$(sed -n '/^ID=/s///p' /etc/os-release)
  if [[ "${distro}" != "debian" ]]; then
    error "Only 'debian' systems are supported!"
    exit $ERR_PRE_REQ
  fi
}


do_upgrade () {
  apt-get --assume-yes update
  apt-get --assume-yes upgrade
  apt-get --assume-yes dist-upgrade
}


setup_data_partition () {
  local data_mount=/mnt/data

  # Ensure the mount directory is empty!
  if [[ $(find "$data_mount" -type f | wc -l) -gt 0 ]]; then
    error "Mount directory '${data_mount}' is not empty!"
    exit $ERR_PRE_REQ
  fi

  # Ensure that we can detect the device.
  local block_dev_name=$(mount -l | grep "${data_mount}" | cut -d' ' -f1)
  if [[ -z "$block_dev_name" ]]; then
    error "Could not find the device for mount '${data_mount}'."
    exit $ERR_PRE_REQ
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
    error "Re-mount error: '${data_mount}' did not auto-mount."
    exit $ERR_RUNTIME
  fi

  # Create symlink-destinations for docker and wodby.
  mkdir "${data_mount}/var-lib-docker" "${data_mount}/srv-wodby"

  # 'rm' will only remove the symlinks, if there are directories it will fail.
  rm -f /srv/wodby /var/lib/docker

  # Create the symlinks to the separate disk.
  ln -s "${data_mount}/var-lib-docker" /var/lib/docker
  ln -s "${data_mount}/srv-wodby" /srv/wodby
  # All done.
}


#
# Actual script: main function
#
main