#!/bin/bash -x
set -o errexit

# This script runs inside the chroot environment
BOOT_DEV=$1

if [[ $2 ]]; then
    crypt=$2
fi

mount none -t proc /proc
mount none -t sysfs /sys
mount none -t devpts /dev/pts
mount ${BOOT_DEV}p1 /mnt/boot

# Setup env
export HOME=/root
export LC_ALL=C

# apt wont ask you questions now, you are welcome
export DEBIAN_FRONTEND=noninteractive

# stop any services from starting (we remove this later)
cat << EOF > /usr/sbin/policy-rc.d
#!/bin/sh
exit 101
EOF
chmod +x /usr/sbin/policy-rc.d

apt-get update
apt-get upgrade -y
# adjust any packages you want to install here, software-properties-common and
# the kernel/kernel headers are required (but they dont have to be vivid)
# vivid is 3.19, I recommend using it
apt-get install -y linux-firmware linux-headers-generic-lts-vivid htop parted \
                   linux-image-generic-lts-vivid intel-microcode bridge-utils \
                   vim ifenslave sudo vlan openssh-server git tmux python-dev \
                   software-properties-common

if [[ "${!crypt[@]}" ]]; then
    apt-get install -y cryptsetup mdadm
fi

# zfs me!
add-apt-repository -y ppa:zfs-native/stable
apt-get update
apt-get upgrade -y
apt-get install -y ubuntu-zfs zfs-initramfs
apt-get clean
update-initramfs -c -k all

# Add a user and set the password to 'a'
useradd -m -s /bin/bash sam
echo -e 'a\na' | passwd sam

# Add a user to sudoers (dont require user to enter password to 'sudo')
echo "sam ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/sam

# Enable pageup and pagedown to scroll through matching history
sed -i 's/.*history-search-backward.*/"\\e[5~": history-search-backward/' /etc/inputrc
sed -i 's/.*history-search-forward.*/"\\e[6~": history-search-forward/' /etc/inputrc

# cleanup
rm /usr/sbin/policy-rc.d
rm -rf /tmp/*
umount /proc /sys /dev/pts /boot
