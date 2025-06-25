#!/bin/bash
set -euo pipefail

# === Config ===
DISTRO_NAME="Archy"
ARCH="amd64"
RELEASE="sid"
MIRROR="http://deb.debian.org/debian"
WORKDIR="$PWD/archy-build"
CHROOT="$WORKDIR/chroot"
ISOFILE="$PWD/${DISTRO_NAME}.iso"

echo "[1/7] 🔍 Checking filesystem type..."
FSTYPE=$(df -T "$PWD" | tail -1 | awk '{print $2}')
if [[ "$FSTYPE" != "ext4" ]]; then
  echo "❌ ERROR: You must run this from an ext4 partition. You're on: $FSTYPE"
  exit 1
fi
echo "✅ Filesystem is ext4"

echo "[2/7] 🔥 Cleaning up old build dir & mounts..."
for d in dev proc sys; do
    sudo umount -lf "$CHROOT/$d" 2>/dev/null || true
done
sudo chattr -i -R "$WORKDIR" 2>/dev/null || true
sudo rm -rf "$WORKDIR"
mkdir -p "$CHROOT"

echo "[3/7] 📦 Installing required packages..."
sudo apt update
sudo apt install -y \
  debootstrap live-build squashfs-tools grub-pc-bin \
  grub-efi-amd64-bin mtools xorriso sudo curl wget

echo "[4/7] 🏗️ Bootstrapping Debian Sid system into $CHROOT"
sudo debootstrap --arch="$ARCH" "$RELEASE" "$CHROOT" "$MIRROR"

echo "[5/7] 🔩 Mounting virtual filesystems for chroot..."
sudo cp /etc/resolv.conf "$CHROOT/etc/"
for dir in dev proc sys; do
    sudo mount --bind /$dir "$CHROOT/$dir"
done

echo "[6/7] 🧰 Configuring Archy inside chroot..."
sudo chroot "$CHROOT" /bin/bash <<'EOL'
set -e
export DEBIAN_FRONTEND=noninteractive
echo "archy" > /etc/hostname

echo "[+] Setting APT sources..."
cat > /etc/apt/sources.list <<EOF
deb http://deb.debian.org/debian sid main contrib non-free non-free-firmware
EOF

apt update
apt install -y locales
locale-gen en_US.UTF-8
export LANG=en_US.UTF-8

echo "[+] Installing base system packages..."
apt install -y \
  systemd systemd-sysv grub-pc grub-efi-amd64-bin linux-image-amd64 \
  net-tools ifupdown isc-dhcp-client iputils-ping \
  ca-certificates curl wget gnupg vim bash-completion \
  live-boot live-config live-build sudo

echo "[+] Creating user archy..."
useradd -m -s /bin/bash archy
echo "archy:archy" | chpasswd
usermod -aG sudo archy

echo "[+] Rebranding Debian to Archy..."
find /etc /usr/share -type f -readable -writable -exec sed -i 's/Debian/Archy/g' {} + 2>/dev/null || true

echo "[+] Cleaning apt cache..."
apt clean
EOL

echo "[+] 🔌 Unmounting chroot mounts..."
for dir in dev proc sys; do
    sudo umount -lf "$CHROOT/$dir" || true
done

echo "[7/7] 💿 Preparing and building ISO..."

cd "$WORKDIR"
mkdir -p config/includes.chroot
cp -aT "$CHROOT" config/includes.chroot

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

sudo lb build

mv live-image-$ARCH.hybrid.iso "$ISOFILE"
echo "✅ ISO successfully built: $ISOFILE"
