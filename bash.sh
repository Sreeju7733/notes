#!/bin/bash
set -euo pipefail

DISTRO_NAME="Archy"
ARCH="amd64"
RELEASE="sid"
MIRROR="http://deb.debian.org/debian"
WORKDIR="$PWD/archy-build"
CHROOT="$WORKDIR/chroot"
ISOFILE="$PWD/${DISTRO_NAME}.iso"

echo "[+] Cleaning previous build..."
sudo rm -rf "$WORKDIR"
mkdir -p "$CHROOT"

echo "[+] Bootstrapping base system..."
sudo debootstrap --arch="$ARCH" "$RELEASE" "$CHROOT" "$MIRROR"

echo "[+] Binding system dirs for chroot..."
for dir in dev proc sys; do
    sudo mount --bind /$dir "$CHROOT/$dir"
done

echo "[+] Configuring chroot environment..."
sudo chroot "$CHROOT" /bin/bash -c "
set -e

echo archy > /etc/hostname

# Set up Sid rolling repo
cat > /etc/apt/sources.list <<EOF
deb $MIRROR sid main contrib non-free non-free-firmware
EOF

apt update
apt install -y locales
locale-gen en_US.UTF-8
export LANG=en_US.UTF-8

echo '[+] Installing core packages...'
apt install -y \
    systemd systemd-sysv grub-pc linux-image-amd64 \
    sudo net-tools ifupdown isc-dhcp-client iputils-ping \
    ca-certificates curl wget gnupg vim bash-completion \
    live-boot live-config live-build

# Create user archy
useradd -m -s /bin/bash archy
echo 'archy:archy' | chpasswd
usermod -aG sudo archy

# Debranding Debian → Archy (safely)
echo '[+] Rebranding...'
find /etc /usr/share -type f -readable -writable -exec sed -i 's/Debian/Archy/g' {} + 2>/dev/null || true
"

echo "[+] Cleaning up chroot..."
for dir in dev proc sys; do
    sudo umount "$CHROOT/$dir" || true
done

echo "[+] Setting up ISO build directory..."
cd "$WORKDIR"
mkdir -p config/includes.chroot
cp -rT "$CHROOT" config/includes.chroot

echo "[+] Creating live-build config..."
lb config noauto \
  --mode debian \
  --architectures "$ARCH" \
  --distribution "$RELEASE" \
  --binary-images iso-hybrid \
  --linux-flavours amd64 \
  --archive-areas "main contrib non-free non-free-firmware" \
  --bootappend-live "boot=live components quiet splash username=archy hostname=archy" \
  --iso-volume "$DISTRO_NAME" \
  --iso-application "$DISTRO_NAME OS" \
  --mirror-bootstrap "$MIRROR" \
  --mirror-chroot "$MIRROR" \
  --mirror-binary "$MIRROR" \
  --debian-installer live

echo "[+] Building ISO (may take time)..."
sudo lb build

mv live-image-$ARCH.hybrid.iso "$ISOFILE"
echo "✅ DONE: Your Archy ISO is ready → $ISOFILE"
