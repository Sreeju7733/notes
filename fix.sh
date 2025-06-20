#!/bin/bash
# Comprehensive chroot repair script with PATH fix
set -e

# Set PATH to include sbin directories
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Verify and fix chroot path
if [ -d "/home/sreeju/archy/archy-build-amd64" ]; then
    CHROOT_DIR="/home/sreeju/archy/archy-build-amd64"
elif [ -d "/archy/archy-build-amd64" ]; then
    CHROOT_DIR="/archy/archy-build-amd64"
else
    read -p "Enter full path to chroot directory: " CHROOT_DIR
    mkdir -p "$CHROOT_DIR"
fi

# Create essential directory structure
mkdir -p "${CHROOT_DIR}"/{bin,dev,etc,lib,lib64,proc,root,sys,tmp,usr,var}
mkdir -p "${CHROOT_DIR}"/usr/{bin,lib,sbin}
mkdir -p "${CHROOT_DIR}"/var/lib/apt
mkdir -p "${CHROOT_DIR}"/dev/pts

# Remove conflicting symlinks
rm -f "${CHROOT_DIR}/bin/bin" 2>/dev/null || true
rm -f "${CHROOT_DIR}/sbin/sbin" 2>/dev/null || true

# Create proper symlinks
ln -sf usr/bin "${CHROOT_DIR}/bin"
ln -sf usr/sbin "${CHROOT_DIR}/sbin"
ln -sf usr/lib "${CHROOT_DIR}/lib"
ln -sf usr/lib64 "${CHROOT_DIR}/lib64"

# Set up temporary resolution
echo "nameserver 8.8.8.8" > "${CHROOT_DIR}/etc/resolv.conf"

# Install minimal binaries using debootstrap
if ! command -v debootstrap >/dev/null; then
    echo "Installing debootstrap..."
    apt-get update
    apt-get install -y debootstrap
fi

# Install minimal Debian system
debootstrap --variant=minbase bookworm "${CHROOT_DIR}" http://deb.debian.org/debian

# Mount virtual filesystems
mount -t proc proc "${CHROOT_DIR}/proc" 2>/dev/null || true
mount -t sysfs sys "${CHROOT_DIR}/sys" 2>/dev/null || true
mount -o bind /dev "${CHROOT_DIR}/dev" 2>/dev/null || true
mount -t devpts devpts "${CHROOT_DIR}/dev/pts" 2>/dev/null || true

# Final configuration inside chroot
chroot "${CHROOT_DIR}" /bin/bash <<'EOL'
#!/bin/bash
set -e

# Basic environment setup
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
export DEBIAN_FRONTEND=noninteractive

# Install essential packages
apt-get update
apt-get install -y --no-install-recommends \
    ca-certificates \
    systemd-sysv \
    udev \
    dbus \
    apt-utils

# Clean up
apt-get clean
rm -rf /var/lib/apt/lists/*

# Verify system
echo "System verification:"
ls -l /bin/bash
command -v apt-get
update-ca-certificates --fresh
command -v grub-probe || echo "grub-probe not installed (normal for minimal system)"
EOL

# Cleanup
umount -l "${CHROOT_DIR}/dev/pts" 2>/dev/null || true
umount -l "${CHROOT_DIR}/dev" 2>/dev/null || true
umount -l "${CHROOT_DIR}/sys" 2>/dev/null || true
umount -l "${CHROOT_DIR}/proc" 2>/dev/null || true

echo "Chroot environment successfully repaired at ${CHROOT_DIR}"
echo "Access with: sudo chroot ${CHROOT_DIR}"
