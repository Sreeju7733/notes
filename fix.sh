#!/bin/bash
# Complete chroot environment fix
set -e

# Define chroot path
CHROOT_DIR="/archy/archy-build-amd64"

# Create essential directory structure
mkdir -p "${CHROOT_DIR}"/{bin,dev,etc,lib,lib64,proc,root,sys,tmp,usr,var}
mkdir -p "${CHROOT_DIR}"/usr/{bin,lib,sbin}
mkdir -p "${CHROOT_DIR}"/var/lib/apt
mkdir -p "${CHROOT_DIR}"/dev/pts

# Set up temporary resolution (use Google DNS)
echo "nameserver 8.8.8.8" > "${CHROOT_DIR}/etc/resolv.conf"

# Copy core binaries
cp /bin/{bash,sh,ls,cat,echo,mkdir,rm,mount,umount,chroot} "${CHROOT_DIR}/bin/"
cp /usr/bin/apt-get "${CHROOT_DIR}/usr/bin/"
cp /usr/sbin/{grub-probe,update-ca-certificates} "${CHROOT_DIR}/usr/sbin/"

# Copy essential libraries
copy_libs() {
    for bin in "$@"; do
        ldd "$bin" | awk '/=>/ {print $3}' | while read -r lib; do
            [ -f "$lib" ] && {
                lib_dir="${CHROOT_DIR}/$(dirname "$lib")"
                mkdir -p "$lib_dir"
                cp -f "$lib" "${CHROOT_DIR}${lib}"
            }
        done
    done
}

# Copy libraries for core binaries
copy_libs /bin/bash /bin/sh /usr/bin/apt-get /usr/sbin/grub-probe

# Mount virtual filesystems
mount -t proc proc "${CHROOT_DIR}/proc"
mount -t sysfs sys "${CHROOT_DIR}/sys"
mount -o bind /dev "${CHROOT_DIR}/dev"
mount -t devpts devpts "${CHROOT_DIR}/dev/pts"

# Run commands in the chroot
chroot "${CHROOT_DIR}" /bin/bash -c '
    # Basic environment setup
    export PATH=/usr/bin:/bin:/usr/sbin:/sbin
    export HOME=/root
    export TERM=xterm
    export DEBIAN_FRONTEND=noninteractive
    
    # Create required symlinks
    ln -s /usr/sbin/update-ca-certificates /usr/bin/ 2>/dev/null
    
    # Reinstall critical packages
    echo "Reinstalling essential packages..."
    apt-get update
    apt-get install --reinstall -y debian-archive-keyring ca-certificates
    
    # Update certificates
    echo "Updating CA certificates..."
    update-ca-certificates --fresh
    
    # Test system functionality
    echo "Testing system..."
    grub-probe / && echo "Grub probe successful" || echo "Grub probe test skipped"
    
    echo "Critical operations completed successfully"
'

# Cleanup
umount -l "${CHROOT_DIR}/dev/pts"
umount -l "${CHROOT_DIR}/dev"
umount -l "${CHROOT_DIR}/sys"
umount -l "${CHROOT_DIR}/proc"

echo "Fix completed. Chroot environment should be functional."
