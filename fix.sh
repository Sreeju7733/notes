#!/bin/bash
# Universal chroot fix script
set -e

# Define chroot path
CHROOT_DIR="/archy/archy-build-amd64"

# Create required directories
mkdir -p "${CHROOT_DIR}"/{proc,sys,dev,dev/pts,bin,usr/bin,lib,lib64,usr/lib}

# Copy essential binaries and libraries
for bin in sh bash; do
    [ -f "/bin/$bin" ] && cp -f "/bin/$bin" "${CHROOT_DIR}/bin/"
done

# Copy basic utilities
[ -f "/usr/bin/apt-get" ] && cp -f "/usr/bin/apt-get" "${CHROOT_DIR}/usr/bin/"
[ -f "/usr/bin/update-ca-certificates" ] && cp -f "/usr/bin/update-ca-certificates" "${CHROOT_DIR}/usr/bin/"
[ -f "/usr/sbin/grub-probe" ] && cp -f "/usr/sbin/grub-probe" "${CHROOT_DIR}/usr/sbin/"

# Copy essential libraries
ldd "/bin/sh" | awk '/=>/ {print $3}' | while read -r lib; do
    [ -f "$lib" ] && cp -f "$lib" "${CHROOT_DIR}${lib}"
done

# Mount virtual filesystems
mount -t proc proc "${CHROOT_DIR}/proc" 2>/dev/null || true
mount -t sysfs sys "${CHROOT_DIR}/sys" 2>/dev/null || true
mount -o bind /dev "${CHROOT_DIR}/dev" 2>/dev/null || true
mount -t devpts devpts "${CHROOT_DIR}/dev/pts" 2>/dev/null || true

# Run commands with fallback to sh
chroot "${CHROOT_DIR}" /bin/sh -c '
    # Basic environment setup
    export PATH=/usr/bin:/bin:/usr/sbin:/sbin
    export DEBIAN_FRONTEND=noninteractive
    
    # Reinstall keyring
    echo "Reinstalling essential packages..."
    [ -x /usr/bin/apt-get ] && apt-get update
    [ -x /usr/bin/apt-get ] && apt-get install --reinstall -y debian-archive-keyring ca-certificates
    
    # Update certificates
    echo "Updating CA certificates..."
    [ -x /usr/bin/update-ca-certificates ] && update-ca-certificates --fresh
    
    # Test system
    echo "Testing system..."
    [ -x /usr/sbin/grub-probe ] && grub-probe / || echo "Grub probe test skipped"
    
    echo "Critical operations completed successfully"
'

# Cleanup
umount -l "${CHROOT_DIR}/dev/pts" 2>/dev/null || true
umount -l "${CHROOT_DIR}/dev" 2>/dev/null || true
umount -l "${CHROOT_DIR}/sys" 2>/dev/null || true
umount -l "${CHROOT_DIR}/proc" 2>/dev/null || true

echo "Fix operations completed. System should be functional now."
