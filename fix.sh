#!/bin/bash
# Fix script for Arch Linux build environment
set -e

# Define chroot path (adjust if different)
CHROOT_DIR="/archy/archy-build-amd64"

# Mount virtual filesystems
mount -t proc proc "${CHROOT_DIR}/proc"
mount -t sysfs sys "${CHROOT_DIR}/sys"
mount -o bind /dev "${CHROOT_DIR}/dev"
mount -t devpts devpts "${CHROOT_DIR}/dev/pts"

# Re-run critical operations inside chroot
chroot "${CHROOT_DIR}" /bin/bash <<'EOL'
set -e
echo "Reinstalling debian-archive-keyring..."
apt-get install --reinstall -y debian-archive-keyring
echo "Updating CA certificates..."
update-ca-certificates --fresh
echo "Testing system devices..."
grub-probe /
EOL

# Cleanup (optional)
umount "${CHROOT_DIR}/dev/pts"
umount "${CHROOT_DIR}/dev"
umount "${CHROOT_DIR}/sys"
umount "${CHROOT_DIR}/proc"

echo "Fixed successfully. Critical operations completed."
