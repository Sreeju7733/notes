#!/bin/bash
# Complete Debian chroot builder
set -e

# Configuration
CHROOT_DIR="/archy/archy-build-amd64"
DEBIAN_RELEASE="bullseye"  # Change to bookworm or sid if needed
ARCH="amd64"
MIRROR="http://deb.debian.org/debian"

# Create directory structure
mkdir -p "${CHROOT_DIR}"
cd "${CHROOT_DIR}"
mkdir -p {bin,boot,dev,etc,home,lib,lib64,media,mnt,opt,proc,root,run,sbin,srv,sys,tmp,usr,var}
mkdir -p usr/{bin,lib,sbin,share,include}
mkdir -p var/{log,lib,cache,spool}
mkdir -p dev/pts
ln -s usr/bin bin
ln -s usr/sbin sbin
ln -s usr/lib lib
ln -s usr/lib64 lib64

# Set up temporary filesystem mounts
mount -t proc proc proc
mount -t sysfs sys sys
mount -o bind /dev dev
mount -t devpts devpts dev/pts

# Create essential files
cat > etc/resolv.conf <<EOF
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF

echo "debian-chroot" > etc/hostname

cat > etc/hosts <<EOF
127.0.0.1 localhost
::1 localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF

# Install debootstrap if missing
if ! command -v debootstrap >/dev/null; then
    echo "Installing debootstrap..."
    apt-get update
    apt-get install -y debootstrap
fi

# Bootstrap Debian system
debootstrap --arch="${ARCH}" "${DEBIAN_RELEASE}" "${CHROOT_DIR}" "${MIRROR}"

# Configure basic system
chroot "${CHROOT_DIR}" /bin/bash <<'EOL'
set -e
# Create required symlinks
ln -sf /proc/self/mounts /etc/mtab

# Configure locales
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen en_US.UTF-8
update-locale LANG=en_US.UTF-8

# Install essential packages
apt-get update
apt-get install -y --no-install-recommends \
    ca-certificates \
    systemd-sysv \
    udev \
    dbus \
    netbase \
    ifupdown \
    iproute2 \
    isc-dhcp-client \
    sudo \
    apt-utils \
    less \
    vim-tiny

# Set up root password
echo "root:password" | chpasswd

# Create default user
useradd -m -s /bin/bash user
echo "user:password" | chpasswd
usermod -aG sudo user

# Configure network
cat > /etc/network/interfaces <<EOF
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
EOF

# Enable basic services
systemctl enable systemd-networkd
systemctl enable systemd-resolved

# Clean package cache
apt-get clean
rm -rf /var/lib/apt/lists/*
EOL

# Finalize
umount dev/pts
umount dev
umount sys
umount proc

echo "Debian chroot successfully created at ${CHROOT_DIR}"
echo "Access with: sudo chroot ${CHROOT_DIR}"
