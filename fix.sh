#!/bin/bash
# Complete chroot environment fix - updated path version
set -e

# Define chroot path
CHROOT_DIR="/archy/archy-build-amd64"

# Create essential directory structure
mkdir -p "${CHROOT_DIR}"/{bin,dev,etc,lib,lib64,proc,root,sys,tmp,usr,var}
mkdir -p "${CHROOT_DIR}"/usr/{bin,lib,sbin}
mkdir -p "${CHROOT_DIR}"/var/lib/apt
mkdir -p "${CHROOT_DIR}"/dev/pts

# Set up temporary resolution
echo "nameserver 8.8.8.8" > "${CHROOT_DIR}/etc/resolv.conf"

# Copy core binaries from their actual locations
copy_bin() {
    src="$1"
    dest="$2"
    [ -f "$src" ] && cp -f "$src" "$dest" || echo "Warning: $src not found"
}

# Copy essential binaries
copy_bin /bin/bash "${CHROOT_DIR}/bin/"
copy_bin /bin/sh "${CHROOT_DIR}/bin/"
copy_bin /bin/ls "${CHROOT_DIR}/bin/"
copy_bin /bin/cat "${CHROOT_DIR}/bin/"
copy_bin /bin/echo "${CHROOT_DIR}/bin/"
copy_bin /bin/mkdir "${CHROOT_DIR}/bin/"
copy_bin /bin/rm "${CHROOT_DIR}/bin/"
copy_bin /bin/mount "${CHROOT_DIR}/bin/"
copy_bin /bin/umount "${CHROOT_DIR}/bin/"
copy_bin /usr/bin/chroot "${CHROOT_DIR}/usr/bin/"  # Corrected chroot path
copy_bin /usr/bin/apt-get "${CHROOT_DIR}/usr/bin/"
copy_bin /usr/sbin/grub-probe "${CHROOT_DIR}/usr/sbin/"
copy_bin /usr/sbin/update-ca-certificates "${CHROOT_DIR}/usr/sbin/"

# Copy essential libraries
copy_libs() {
    for bin in "$@"; do
        ldd "$bin" 2>/dev/null | awk '/=>/ {print $3}' | while read -r lib; do
            [ -f "$lib" ] && {
                lib_dir="${CHROOT_DIR}/$(dirname "$lib")"
                mkdir -p "$lib_dir"
                cp -f "$lib" "${CHROOT_DIR}${lib}" 2>/dev/null || true
            }
        done
    done
}

# Copy libraries for core binaries
copy_libs /bin/bash /bin/sh /usr/bin/apt-get /usr/sbin/grub-probe /usr/bin/chroot

# Mount virtual filesystems
mount -t proc proc "${CHROOT_DIR}/proc" || echo "Mounting proc failed (might already be mounted)"
mount -t sysfs sys "${CHROOT_DIR}/sys" || echo "Mounting sys failed (might already be mounted)"
mount -o bind /dev "${CHROOT_DIR}/dev" || echo "Binding /dev failed (might already be mounted)"
mount -t devpts devpts "${CHROOT_DIR}/dev/pts" || echo "Mounting devpts failed (might already be mounted)"

# Run commands in the chroot
chroot "${CHROOT_DIR}" /bin/bash -c '
    # Basic environment setup
    export PATH=/usr/bin:/bin:/usr/sbin:/sbin
    export HOME=/root
    export TERM=xterm
    export DEBIAN_FRONTEND=noninteractive
    
    # Create required symlinks
    ln -sf /usr/sbin/update-ca-certificates /usr/bin/update-ca-certificates 2>/dev/null
    
    # Reinstall critical packages
    echo "Reinstalling essential packages..."
    apt-get update || echo "apt-get update failed, continuing anyway"
    apt-get install --reinstall -y debian-archive-keyring ca-certificates || echo "Package reinstall failed"
    
    # Update certificates
    echo "Updating CA certificates..."
    update-ca-certificates --fresh || echo "Certificate update failed"
    
    # Test system functionality
    echo "Testing system..."
    if command -v grub-probe &>/dev/null; then
        grub-probe / && echo "Grub probe successful" || echo "Grub probe test failed"
    else
        echo "grub-probe not found, test skipped"
    fi
    
    echo "Critical operations completed"
'

# Cleanup
umount -l "${CHROOT_DIR}/dev/pts" 2>/dev/null || true
umount -l "${CHROOT_DIR}/dev" 2>/dev/null || true
umount -l "${CHROOT_DIR}/sys" 2>/dev/null || true
umount -l "${CHROOT_DIR}/proc" 2>/dev/null || true

echo "Fix operations completed. Check output for any errors."
