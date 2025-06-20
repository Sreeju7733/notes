#!/bin/bash
# Direct repair script for Arch Linux build environment
set -e

# Define chroot path
CHROOT_DIR="/archy/archy-build-amd64"

# 1. Ensure essential mounts exist
mkdir -p "${CHROOT_DIR}/proc"
mkdir -p "${CHROOT_DIR}/sys"
mkdir -p "${CHROOT_DIR}/dev"
mkdir -p "${CHROOT_DIR}/dev/pts"

# 2. Mount required filesystems
mount -t proc proc "${CHROOT_DIR}/proc" 2>/dev/null || true
mount -t sysfs sys "${CHROOT_DIR}/sys" 2>/dev/null || true
mount -o bind /dev "${CHROOT_DIR}/dev" 2>/dev/null || true
mount -t devpts devpts "${CHROOT_DIR}/dev/pts" 2>/dev/null || true

# 3. Execute repair commands using system chroot
chroot "${CHROOT_DIR}" /bin/sh -c '
    # Basic environment setup
    export PATH=/usr/bin:/bin:/usr/sbin:/sbin
    export HOME=/root
    export TERM=xterm
    export DEBIAN_FRONTEND=noninteractive
    
    # Create essential symlinks if missing
    [ ! -e /bin/sh ] && ln -s /usr/bin/bash /bin/sh 2>/dev/null
    [ ! -e /usr/bin/apt-get ] && ln -s /usr/bin/apt /usr/bin/apt-get 2>/dev/null
    
    # Reinstall critical packages
    echo "Attempting package repair..."
    if command -v apt-get >/dev/null; then
        apt-get update || echo "apt-get update failed - continuing"
        apt-get install --reinstall -y --allow-downgrades \
            debian-archive-keyring \
            ca-certificates \
            base-files \
            libc6 || echo "Package reinstallation encountered errors"
    else
        echo "apt-get not found - attempting manual certificate installation"
        mkdir -p /usr/share/ca-certificates/mozilla
        update-ca-certificates --fresh
    fi
    
    # Verify system state
    echo "System status:"
    echo -n "Bash: "; command -v bash || echo "missing"
    echo -n "apt-get: "; command -v apt-get || echo "missing"
    echo -n "grub-probe: "; command -v grub-probe || echo "missing"
    
    # Final test
    echo "Testing root filesystem..."
    ls -l / >/dev/null && echo "Root FS accessible" || echo "Root FS inaccessible"
    
    echo "Repair operations completed. Check output for any issues."
'

# 4. Cleanup mounts
umount -l "${CHROOT_DIR}/dev/pts" 2>/dev/null || true
umount -l "${CHROOT_DIR}/dev" 2>/dev/null || true
umount -l "${CHROOT_DIR}/sys" 2>/dev/null || true
umount -l "${CHROOT_DIR}/proc" 2>/dev/null || true

echo "Repair script finished. If problems persist, consider recreating the build environment."
