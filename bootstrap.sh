#!/bin/bash -x
# We will exit on any non-zero exit code
set -o errexit

# Commands ending it " # luks_commands" can be ignored if not using luks

# USAGE: ./bootstrap.sh
# its expected you run it exactly as the usage. Things will break otherwise

### WARNING WARNING WARNING ###
# This is really destructive, so whatever disk you have here will get repartitioned and formated. You've been warned
BOOT_DEV=/dev/sda

# creating the zpool -o is zpool properties, -O is zfs properties DO NOT ADJUST ashift=12 UNLESS YOU KNOW WHY YOU ARE DOING IT, its really important
# /dev/mapper/zfs01 is a LUKS volume, you can put /dev/sd? here
# This creates a mirror set
zpool create -f -o ashift=12 -o cachefile=/tmp/zpool.cache -O compression=lz4 -O atime=off -O dedup=on -O sync=disabled -m none -R /mnt rpool mirror /dev/mapper/zfs01 /dev/mapper/zfs02
#zpool create -f -o ashift=12 -o cachefile=/tmp/zpool.cache -O compression=lz4 -O atime=off -O dedup=on -O sync=disabled -m none -R /mnt rpool /dev/mapper/zfs01
zfs create -o mountpoint=none rpool/ROOT
zfs create -o mountpoint=/ rpool/ROOT/ubuntu
zfs create -o mountpoint=/home rpool/HOME
zfs create -o mountpoint=/root rpool/HOME/root
zpool set bootfs=rpool/ROOT/ubuntu rpool

debootstrap trusty /mnt/

mount -t proc none /mnt/proc
mount --rbind /sys /mnt/sys
mount --make-rslave /mnt/sys
mount --rbind /dev /mnt/dev
mount --make-rslave /mnt/dev

### WARNING WARNING WARNING ###
# Formatting is happening
parted $BOOT_DEV -s -- mklabel msdos mkpart pri 1 1G set 1 boot on
wipefs -a ${BOOT_DEV}1
mkfs.ext4 ${BOOT_DEV}1
mount ${BOOT_DEV}1 /mnt/boot
ln -sf /dev/mapper/zfs01 /dev/zfs01 # luks_commands
ln -sf /dev/mapper/zfs02 /dev/zfs02 # luks_commands

# Write out bootstrap script to be run inside the chroot
cat << EOT > /mnt/bootstrap_chroot.sh
#!/bin/bash -x
set -o errexit

# apt wont ask you questions now, you are welcome
export DEBIAN_FRONTEND=noninteractive

# gen locale to prevent wierd unicode crap
locale-gen en_US.UTF-8

# Set hostname
echo server01 > /etc/hostname

# stop any services from starting (we remove this later)
cat << EOF > /usr/sbin/policy-rc.d
#!/bin/sh
exit 101
EOF
chmod +x /usr/sbin/policy-rc.d

apt-get update
apt-get upgrade -y
# adjust any packages you want to install here, software-properties-common and the kernel/kernel headers are required (but they dont have to be vivid)
# vivid is 3.19, i recommend using it
apt-get install -y linux-firmware linux-headers-generic-lts-vivid linux-image-generic-lts-vivid intel-microcode bridge-utils vim tmux htop ifenslave sudo vlan openssh-server software-properties-common cryptsetup

# zfs me!
add-apt-repository -y ppa:zfs-native/stable
apt-get update
apt-get install -y ubuntu-zfs zfs-initramfs grub2

echo -e "zfs01 UUID=5e75afff-8b2f-49d1-9fa7-cd59de9d5a04 none luks,discard" > /etc/crypttab # luks_commands
echo -e "zfs02 UUID=1fb49f29-3a44-4885-990e-ac518c32fea0 zfs01 luks,discard,keyscript=/lib/cryptsetup/scripts/decrypt_derived" >> /etc/crypttab # luks_commands
echo 'ENV{DM_NAME}=="zfs01", SYMLINK+="zfs01"' > /etc/udev/rules.d/99-zfs.rules # luks_commands
echo 'ENV{DM_NAME}=="zfs02", SYMLINK+="zfs02"' >> /etc/udev/rules.d/99-zfs.rules # luks_commands

# disable quiet to see additional startup information, enable boot from zfs
sed -i 's|quiet splash|boot=zfs|' /etc/default/grub

# regen the initramfs to include zfs, install grub, update the grub config
update-initramfs -u -k all
grub-install $BOOT_DEV
update-grub

# cleanup
rm /usr/sbin/policy-rc.d

# Add a user and set the password to 'a'
useradd -m -s /bin/bash sam
echo -e 'a\na' | passwd sam

# Add a user to sudoers (dont require user to enter password to 'sudo')
cat << EOF > /etc/sudoers.d/sam
sam ALL=(ALL) NOPASSWD: ALL
EOF

# Enable pageup and pagedown to scroll through matching history, aka the right way to do it
sed -i 's/.*history-search-backward.*/"\\e[5~": history-search-backward/' /etc/inputrc
sed -i 's/.*history-search-forward.*/"\\e[6~": history-search-forward/' /etc/inputrc

# cleanup
rm /bootstrap_chroot.sh
EOT
chmod +x /mnt/bootstrap_chroot.sh

# This writes the interfaces file out
# bond physical interfaces and add the bond to a bridge, apply ip stuff to bridge
cat << EOF > /mnt/etc/network/interfaces
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet manual
    bond-master bond0

auto eth1
iface eth1 inet manual
    bond-master bond0

auto bond0
iface bond0 inet manual
    slaves none
    bond-primary eth0
    bond-mode active-backup

auto br10
iface br10 inet static
    address 192.168.31.11
    netmask 255.255.255.0
    gateway 192.168.31.251
    dns 8.8.8.8
    bridge-stp off
    bridge-waitport 0
    bridge-fd 0
    bridge-ports bond0
EOF


# Writes out the sources.list
# I recommend not changing this since some packages come from the non-free repo
cat << EOF > /mnt/etc/apt/sources.list
# Base
deb http://us.archive.ubuntu.com/ubuntu/ trusty main restricted universe multiverse
# deb-src http://us.archive.ubuntu.com/ubuntu/ trusty main restricted universe multiverse

# Security
deb http://us.archive.ubuntu.com/ubuntu/ trusty-security main restricted universe multiverse
# deb-src http://us.archive.ubuntu.com/ubuntu/ trusty-security main restricted universe multiverse

# Updates
deb http://us.archive.ubuntu.com/ubuntu/ trusty-updates main restricted universe multiverse
# deb-src http://us.archive.ubuntu.com/ubuntu/ trusty-updates main restricted universe multiverse

# Proposed
# deb http://us.archive.ubuntu.com/ubuntu/ trusty-proposed main restricted universe multiverse
# deb-src http://us.archive.ubuntu.com/ubuntu/ trusty-proposed main restricted universe multiverse

# Backports
# deb http://us.archive.ubuntu.com/ubuntu/ trusty-backports main restricted universe multiverse
# deb-src http://us.archive.ubuntu.com/ubuntu/ trusty-backports main restricted universe multiverse
EOF

# UUID=<BOOT_DEV>, this is the only fstab entry needed (unless you use swap)
echo "UUID="$(blkid ${BOOT_DEV}1 | awk -F\" '{print $2}')" /boot ext4 rw,data=ordered 0 2" > /mnt/etc/fstab

echo "/dev/mapper/zfs01 / zfs defaults 0 0" >> /mnt/etc/fstab # luks_commands
echo 'ENV{DM_NAME}=="zfs01", SYMLINK+="zfs01"' > /mnt/etc/udev/rules.d/99-zfs.rules # luks_commands
echo 'ENV{DM_NAME}=="zfs02", SYMLINK+="zfs02"' >> /mnt/etc/udev/rules.d/99-zfs.rules # luks_commands

# execute script in chroot
chroot /mnt ./bootstrap_chroot.sh

# cp in zpool cache file
cp /tmp/zpool.cache /mnt/etc/zfs/
cp bootstrap.sh /mnt/root/bootstrap.sh

# turn sync back on (set it to default of 'standard')
zfs inherit sync rpool

# exit here if you want to get into the chroot and do other things/install packages/passwd
#exit

# unmount system running systemd
#umount /mnt/{sys{/fs{/cgroup{/systemd,/cpuset,/cpu\,cpuacct,/devices,/freezer,/net_cls\,net_prio,/blkio,/perf_event,},/pstore,/fuse/connections},/kernel/{security,debug},},dev{/shm,/pts,/hugepages,/mqueue,},proc,boot}


# Run these commands at any time to unmount and export the zpool. Once the zpool is exported you can rerun the bootstrap script to start over (wipes all files)
# Non-systemd
umount /mnt/{sys{/kernel/{security,debug},/fs/{cgroup{/systemd,},fuse/connections,pstore},},dev{/pts,},proc,boot}
zpool export rpool
