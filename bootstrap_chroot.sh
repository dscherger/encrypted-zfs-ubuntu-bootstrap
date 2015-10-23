#!/bin/bash -x
set -o errexit

# This script runs inside the chroot environment
BOOT_DEV=$1

if [[ $2 ]]; then
    crypt=$2
fi

# apt wont ask you questions now, you are welcome
export DEBIAN_FRONTEND=noninteractive
export HOME=/root
export LC_ALL=C

# Set hostname
echo server02 > /etc/hostname

# stop any services from starting (we remove this later)
cat << EOF > /usr/sbin/policy-rc.d
#!/bin/sh
exit 101
EOF
chmod +x /usr/sbin/policy-rc.d

echo "Acquire::http::Proxy \"http://192.168.31.11:3142\";" > /etc/apt/apt.conf

apt-get update
apt-get upgrade -y
# adjust any packages you want to install here, software-properties-common and
# the kernel/kernel headers are required (but they dont have to be vivid)
# vivid is 3.19, I recommend using it
apt-get install -y linux-firmware linux-headers-generic-lts-vivid htop parted man \
                   linux-image-generic-lts-vivid intel-microcode bridge-utils mlocate \
                   vim git ifenslave sudo vlan openssh-server tmux python-dev \
                   software-properties-common mdadm

if [[ "${!crypt[@]}" ]]; then
    apt-get install -y cryptsetup
    patch /usr/share/initramfs-tools/hooks/cryptroot < /cryptroot.patch
fi

# zfs me!
add-apt-repository -y ppa:zfs-native/stable
apt-get update
apt-get install -y ubuntu-zfs zfs-initramfs grub2

# Update grub
source /etc/default/grub
sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"${GRUB_CMDLINE_LINUX_DEFAULT} boot=zfs\"|" /etc/default/grub

# regen the initramfs to include zfs, install grub, update the grub config
update-initramfs -c -k all
for DEV in $(echo ${BOOT_DEV} | tr ',' ' '); do
    grub-install ${DEV}
done
update-grub

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
