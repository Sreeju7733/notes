#!/bin/bash
# Fixed script with directory creation
set -e

# Define chroot path
CHROOT_DIR="/archy/archy-build-amd64"

# Create required mount point directories
mkdir -p "${CHROOT_DIR}/proc"
mkdir -p "${CHROOT_DIR}/sys"
mkdir -p "${CHROOT_DIR}/dev/pts"

# Mount virtual filesystems
mount -t proc proc "${CHROOT_DIR}/proc" || { echo "Mounting proc failed"; exit 1; }
mount -t sysfs sys "${CHROOT_DIR}/sys" || { echo "Mounting sys failed"; exit 1; }
mount -o bind /dev "${CHROOT_DIR}/dev" || { echo "Binding /dev failed"; exit 1; }
mount -t devpts devpts "${CHROOT_DIR}/dev/pts" || { echo "Mounting devpts failed"; exit 1; }

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

# Cleanup
umount "${CHROOT_DIR}/dev/pts"
umount "${CHROOT_DIR}/dev"
umount "${CHROOT_DIR}/sys"
umount "${CHROOT_DIR}/proc"

echo "Fixed successfully. Critical operations completed."
