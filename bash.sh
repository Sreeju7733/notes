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

# === Cleanup ===
echo "[+] Cleaning previous build..."
sudo umount "$CHROOT/dev" || true
sudo umount "$CHROOT/proc" || true
sudo umount "$CHROOT/sys" || true
sudo rm -rf "$WORKDIR"
mkdir -p "$CHROOT"

# === Step 1: Bootstrap Sid
echo "[+] Bootstrapping Debian Sid..."
sudo debootstrap --arch="$ARCH" "$RELEASE" "$CHROOT" "$MIRROR"

# === Step 2: Mount /dev, /proc, /sys
echo "[+] Mounting virtual filesystems..."
sudo cp /etc/resolv.conf "$CHROOT/etc/"
for dir in dev proc sys; do
    sudo mount --bind /$dir "$CHROOT/$dir"
done

# === Step 3: Chroot Setup ===
echo "[+] Configuring system in chroot..."
sudo chroot "$CHROOT" /bin/bash <<'EOL'
set -e

# Non-interactive mode
export DEBIAN_FRONTEND=noninteractive

# Hostname
echo archy > /etc/hostname

# Repos (Sid only)
cat > /etc/apt/sources.list <<EOF
deb http://deb.debian.org/debian sid main contrib non-free non-free-firmware
EOF

apt update
apt -y install locales
locale-gen en_US.UTF-8
export LANG=en_US.UTF-8

# Install base system packages
apt install -y \
    systemd systemd-sysv grub-pc linux-image-amd64 \
    sudo net-tools ifupdown isc-dhcp-client iputils-ping \
    ca-certificates curl wget gnupg vim bash-completion \
    live-boot live-config live-build

# Fix: Preconfigure keyboard to avoid broken prompt
echo 'keyboard-configuration keyboard-configuration/layoutcode select us' | debconf-set-selections
echo 'keyboard-configuration keyboard-configuration/modelcode select pc105' | debconf-set-selections
apt purge -y keyboard-configuration console-setup || true

# Add user
useradd -m -s /bin/bash archy
echo "archy:archy" | chpasswd
usermod -aG sudo archy

# Debrand Debian → Archy
echo "[*] Debranding system..."
find /etc /usr/share -type f -readable -writable -exec sed -i 's/Debian/Archy/g' {} + 2>/dev/null || true

EOL

# === Step 4: Unmount
echo "[+] Unmounting virtual filesystems..."
for dir in dev proc sys; do
    sudo umount "$CHROOT/$dir" || true
done

# === Step 5: ISO Build Setup
echo "[+] Preparing ISO build..."
cd "$WORKDIR"
mkdir -p config/includes.chroot
cp -aT "$CHROOT" config/includes.chroot

# === Step 6: live-build Config
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

# === Step 7: Build ISO
echo "[+] Building ISO (grab some coffee
