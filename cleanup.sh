#!/bin/bash

set -o errexit

crypt=$1

# Run these commands at any time to unmount and export the zpool. Once the zpool is exported you can rerun the bootstrap script to start over (wipes all files)
# Non-systemd
umount /mnt/{sys{/kernel/{security,debug},/fs/{cgroup{/systemd,},fuse/connections,pstore},},dev{/pts,},proc,boot} || :
zpool export rpool

if [[ "${!crypt[@]}" ]]; then
    cryptsetup luksClose zfs01
    cryptsetup luksClose zfs02
fi
