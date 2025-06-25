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

# === Full Cleanup ===
echo "[+] Cleaning up any old build..."
sudo umount "$CHROOT/dev" || true
sudo umount "$CHROOT/proc" || true
sudo umount "$CHROOT/sys" || true
sudo rm -rf "$WORKDIR"
mkdir -p "$CHROOT"

# === Step 1: Bootstrap Debian Sid
echo "[+] Bootstrapping Debian Sid into chroot..."
sudo debootstrap --arch="$ARCH" "$RELEASE" "$CHROOT" "$MIRROR"

# === Step 2: Bind mounts
echo "[+] Mounting virtual filesystems..."
sudo cp /etc/resolv.conf "$CHROOT/etc/"
for dir in dev proc sys; do
  sudo mount --bind /$dir "$CHROOT/$dir"
done

# === Step 3: Configure chroot system
echo "[+] Entering chroot and setting up Archy base..."
sudo chroot "$CHROOT" /bin/bash <<'EOL'
set -e

# Set hostname
echo archy > /etc/hostname

# Set up correct sources.list (Sid only)
cat > /etc/apt/sources.list <<EOF
deb http://deb.debian.org/debian sid main contrib non-free non-free-firmware
EOF

# Locale
apt update
apt -y install locales
locale-gen en_US.UTF-8
export LANG=en_US.UTF-8

# Install core packages
apt install -y \
    systemd systemd-sysv grub-pc linux-image-amd64 \
    sudo net-tools ifupdown isc-dhcp-client iputils-ping \
    ca-certificates curl wget gnupg vim bash-completion \
    live-boot live-config live-build

# Create user archy
useradd -m -s /bin/bash archy
echo "archy:archy" | chpasswd
usermod -aG sudo archy

# Debrand Debian → Archy
echo "[*] Debranding..."
find /etc /usr/share -type f -readable -writable -exec sed -i 's/Debian/Archy/g' {} + 2>/dev/null || true

EOL

# === Step 4: Unmount
echo "[+] Cleaning up mounts..."
for dir in dev proc sys; do
  sudo umount "$CHROOT/$dir" || true
done

# === Step 5: Setup ISO
echo "[+] Preparing ISO build..."
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
  --bootappend-live "boot=live components quiet splash username=archy hostname=archy" \
  --iso-volume "$DISTRO_NAME" \
  --iso-application "$DISTRO_NAME OS" \
  --mirror-bootstrap "$MIRROR" \
  --mirror-chroot "$MIRROR" \
  --mirror-binary "$MIRROR" \
  --debian-installer live

# === Step 6: Build the ISO
echo "[+] Building Archy ISO (please wait)..."
sudo lb build

# === Step 7: Rename Output
mv live-image-$ARCH.hybrid.iso "$ISOFILE"
echo "✅ DONE: Your Archy ISO is ready → $ISOFILE"
