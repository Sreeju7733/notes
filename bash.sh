#!/bin/bash
set -euo pipefail

DISTRO_NAME="Archy"
ARCH="amd64"
RELEASE="sid"
MIRROR="http://deb.debian.org/debian"
WORKDIR="$PWD/archy-build"
CHROOT="$WORKDIR/chroot"
ISOFILE="$PWD/${DISTRO_NAME}.iso"

echo "[+] Installing required tools..."
sudo apt update
sudo apt install -y debootstrap live-build squashfs-tools grub-pc-bin grub-efi-amd64-bin mtools xorriso

echo "[+] 🔥 Nuking old build directory..."
sudo umount -lf "$CHROOT/dev" 2>/dev/null || true
sudo umount -lf "$CHROOT/proc" 2>/dev/null || true
sudo umount -lf "$CHROOT/sys" 2>/dev/null || true
sudo chattr -i -R "$WORKDIR" 2>/dev/null || true
sudo rm -rf "$WORKDIR"
mkdir -p "$CHROOT"

echo "[+] 💣 Bootstrapping Debian Sid with --force-overwrite (take that error!)"
sudo debootstrap --arch="$ARCH" --force-overwrite "$RELEASE" "$CHROOT" "$MIRROR"

echo "[+] 🧱 Mounting virtual filesystems..."
sudo cp /etc/resolv.conf "$CHROOT/etc/"
for d in dev proc sys; do
    sudo mount --bind /$d "$CHROOT/$d"
done

echo "[+] 🛠️ Setting up Archy inside chroot..."
sudo chroot "$CHROOT" /bin/bash <<'EOL'
set -e
export DEBIAN_FRONTEND=noninteractive
echo "archy" > /etc/hostname

echo "[+] 📦 Configuring APT sources..."
cat > /etc/apt/sources.list <<EOF
deb http://deb.debian.org/debian sid main contrib non-free non-free-firmware
EOF

apt clean
apt update

echo "[+] 🌍 Generating locale..."
apt install -y locales
locale-gen en_US.UTF-8
export LANG=en_US.UTF-8

echo "[+] 🚀 Installing base packages..."
apt install -y \
  systemd systemd-sysv grub-pc grub-efi-amd64-bin linux-image-amd64 \
  sudo net-tools ifupdown isc-dhcp-client iputils-ping \
  ca-certificates curl wget gnupg vim bash-completion \
  live-boot live-config live-build

echo "[+] ⌨️ Fixing keyboard config..."
echo 'keyboard-configuration keyboard-configuration/layoutcode select us' | debconf-set-selections
echo 'keyboard-configuration keyboard-configuration/modelcode select pc105' | debconf-set-selections
apt purge -y console-setup keyboard-configuration || true

echo "[+] 👤 Creating user archy..."
useradd -m -s /bin/bash archy
echo "archy:archy" | chpasswd
usermod -aG sudo archy

echo "[+] 🎨 Rebranding from Debian to Archy..."
find /etc /usr/share -type f -readable -writable -exec sed -i 's/Debian/Archy/g' {} + 2>/dev/null || true
EOL

echo "[+] 🧼 Unmounting chroot bind mounts..."
for d in dev proc sys; do
    sudo umount -lf "$CHROOT/$d" || true
done

echo "[+] 📁 Preparing live-build configuration..."
cd "$WORKDIR"
mkdir -p config/includes.chroot
cp -aT "$CHROOT" config/includes.chroot

echo "[+] 🔧 Configuring live-build (ISO setup)..."
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

echo "[+] 🏗️ Building the ISO..."
sudo lb build

echo "[+] 💾 Moving ISO to final location..."
mv live-image-$ARCH.hybrid.iso "$ISOFILE"

echo "✅ Archy ISO ready: $ISOFILE"
