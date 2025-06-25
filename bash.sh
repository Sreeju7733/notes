#!/bin/bash
set -euo pipefail

DISTRO_NAME="Archy"
ARCH="amd64"
RELEASE="sid"
MIRROR="http://deb.debian.org/debian"
WORKDIR="$PWD/archy-build"
CHROOT="$WORKDIR/chroot"
ISOFILE="$PWD/${DISTRO_NAME}.iso"

echo "[+] Installing required packages..."
sudo apt update
sudo apt install -y debootstrap live-build squashfs-tools grub-pc-bin grub-efi-amd64-bin grub-efi-bin mtools xorriso

echo "[+] Cleaning old build..."
sudo umount "$CHROOT/dev" || true
sudo umount "$CHROOT/proc" || true
sudo umount "$CHROOT/sys" || true
sudo rm -rf "$WORKDIR"
mkdir -p "$CHROOT"

echo "[+] Bootstrapping Debian Sid base..."
sudo debootstrap --arch="$ARCH" "$RELEASE" "$CHROOT" "$MIRROR"

echo "[+] Mounting virtual filesystems..."
sudo cp /etc/resolv.conf "$CHROOT/etc/"
for dir in dev proc sys; do
    sudo mount --bind /$dir "$CHROOT/$dir"
done

echo "[+] Setting up inside chroot..."
sudo chroot "$CHROOT" /bin/bash <<'EOL'
set -e
export DEBIAN_FRONTEND=noninteractive

echo "archy" > /etc/hostname

cat > /etc/apt/sources.list <<EOF
deb http://deb.debian.org/debian sid main contrib non-free non-free-firmware
EOF

apt clean
apt update

echo "[+] Installing base system..."
apt install -y locales
locale-gen en_US.UTF-8
export LANG=en_US.UTF-8

apt install -y \
    systemd systemd-sysv grub-pc grub-efi-amd64-bin linux-image-amd64 \
    sudo net-tools ifupdown isc-dhcp-client iputils-ping \
    ca-certificates curl wget gnupg vim bash-completion \
    live-boot live-config live-build

echo "[+] Disabling interactive keyboard config..."
echo 'keyboard-configuration keyboard-configuration/layoutcode select us' | debconf-set-selections
echo 'keyboard-configuration keyboard-configuration/modelcode select pc105' | debconf-set-selections
apt purge -y console-setup keyboard-configuration || true

echo "[+] Creating user 'archy' with sudo access..."
useradd -m -s /bin/bash archy
echo "archy:archy" | chpasswd
usermod -aG sudo archy

echo "[+] Rebranding to Archy..."
find /etc /usr/share -type f -readable -writable -exec sed -i 's/Debian/Archy/g' {} + 2>/dev/null || true
EOL

echo "[+] Unmounting chroot..."
for dir in dev proc sys; do
    sudo umount "$CHROOT/$dir" || true
done

echo "[+] Preparing live-build config..."
cd "$WORKDIR"
mkdir -p config/includes.chroot
cp -aT "$CHROOT" config/includes.chroot

echo "[+] Configuring live-build..."
lb config noauto \
  --mode debian \
  --architectures "$ARCH" \
  --distribution "$RELEASE" \
  --binary-images iso-hybrid \
  --linux-flavours amd64 \
  --archive-areas "main contrib non-free non-free-firmware" \
  --bootappend-live "boot=live components username=archy hostname=archy live-config.noconfig keyboard" \
  --iso-volume "$DISTRO_NAME" \
  --iso-application "$DISTRO_NAME OS" \
  --mirror-bootstrap "$MIRROR" \
  --mirror-chroot "$MIRROR" \
  --mirror-binary "$MIRROR" \
  --debian-installer live

echo "[+] Building ISO... This will take a while ☕"
sudo lb build

echo "[+] Moving final ISO to $ISOFILE..."
mv live-image-$ARCH.hybrid.iso "$ISOFILE"

echo "✅ DONE: Your Archy ISO is ready → $ISOFILE"
