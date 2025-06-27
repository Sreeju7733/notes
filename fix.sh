#!/bin/bash
set -euo pipefail

CHROOT="/home/sreeju/os1/archy-build/chroot"

echo "[+] Archy Fixer Script Starting..."

# --- Step 1: Fix hostname resolution ---
echo "[+] Fixing hostname resolution..."
echo "archy" > "$CHROOT/etc/hostname"
echo "127.0.0.1 localhost archy" > "$CHROOT/etc/hosts"

# --- Step 2: Fix DNS ---
echo "[+] Copying DNS config..."
cp /etc/resolv.conf "$CHROOT/etc/resolv.conf"

# --- Step 3: Mount essential virtual filesystems ---
echo "[+] Mounting dev, proc, sys, dev/pts..."
mount --bind /dev "$CHROOT/dev"
mount --bind /proc "$CHROOT/proc"
mount --bind /sys "$CHROOT/sys"
mount -t devpts devpts "$CHROOT/dev/pts"

# --- Step 4: Enter chroot and fix APT ---
echo "[+] Entering chroot and fixing APT..."
chroot "$CHROOT" /bin/bash -c "
set -e
export DEBIAN_FRONTEND=noninteractive
echo '[+] Setting up sources.list...'
cat > /etc/apt/sources.list <<EOF
deb http://deb.debian.org/debian sid main contrib non-free non-free-firmware
EOF

echo '[+] Updating package list...'
apt update

echo '[+] Upgrading base system...'
apt -y upgrade

echo '[+] Optional: Install vim or debug tools here if needed.'
"

# --- Step 5: Cleanup mounts ---
echo "[+] Cleaning up mounts..."
umount -lf "$CHROOT/dev/pts" || true
umount -lf "$CHROOT/dev" || true
umount -lf "$CHROOT/proc" || true
umount -lf "$CHROOT/sys" || true

echo "✅ Archy fix complete. You are good to go!"
