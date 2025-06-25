#!/bin/bash
set -euo pipefail

# === CONFIGURATION ===
DISTRO_NAME="Archy"
ARCH="amd64"
RELEASE="sid"
MIRROR="http://deb.debian.org/debian"
WORKDIR="$PWD/archy-build"
CHROOT="$WORKDIR/chroot"
ISOFILE="$PWD/${DISTRO_NAME}.iso"

echo "[+] Installing required packages..."
sudo apt update
sudo apt install -y \
  debootstrap live-build squashfs-tools grub-pc-bin \
  grub-efi-amd64-bin mtools xorriso

echo "[+] Cleaning old chroot and mount points..."
if mountpoint -q "$CHROOT/dev"; then sudo umount "$CHROOT/dev"; fi
if mountpoint -q "$CHROOT/proc"; then sudo umount "$CHROOT/proc"; fi
if mountpoint -q "$CHROOT/sys"; then sudo umount "$CHROOT/sys"; fi
sudo rm -rf "$CHROOT"
sudo mkdir -p "$CHROOT"

echo "[+] Bootstrapping Debian Sid base system..."
sudo debootstrap --arch="$ARCH" "$RELEASE" "$CHROOT" "$MIRROR"

echo "[+] Mounting virtual filesystems..."
sudo cp /etc/resolv.conf "$CHROOT/etc/"
for dir in dev proc sys; do
    sudo mount --bind /$dir "$CHROOT/$dir"
done

echo "[+] Running system setup in chroot..."
sudo chroot "$CHROOT" /bin/bash <<'EOL'
set -e
export DEBIAN_FRONTEND=noninteractive

echo "archy" > /etc/hostname

# Add Debian Sid sources
cat > /etc/apt/sources.list <<EOF
deb http://deb.debian.org/debian sid main contrib non-free non-free-firmware
EOF

apt clean
apt update

# Set locale
apt install -y locales
locale-gen en_US.UTF-8
export LANG=en_US.UTF-8

# Base system install
apt install -y \
  systemd systemd-sysv grub-pc grub-efi-amd64-bin linux-image-amd64 \
  sudo net-tools ifupdown isc-dhcp-client iputils-ping \
  ca-certificates curl wget gnupg vim bash-completion \
  live-boot live-config live-build

# Keyboard config fix
echo 'keyboard-configuration keyboard-configuration/layoutcode select us' | debconf-set-selections
echo 'keyboard-configuration keyboard-configuration/modelcode select pc105' | debconf-set-selections
apt purge -y console-setup keyboard-configuration || true

# Create user
useradd -m -s /bin/bash archy
echo "archy:archy" | chpasswd
usermod -aG sudo archy

# Rebrand to Archy
find /etc /usr/share -type f -readable -writable \
  -exec sed -i 's/Debian/Archy/g' {} + 2>/dev/null || true
EOL

echo "[+] Unmounting virtual filesystems..."
for dir in dev proc sys; do
    sudo umount "$CHROOT/$dir" || true
done

echo "[+] Preparing live-build structure..."
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

echo "[+] Building ISO image... This will take a few minutes..."
sudo lb build

echo "[+] Moving final ISO to: $ISOFILE"
mv live-image-$ARCH.hybrid.iso "$ISOFILE"

echo "✅ DONE! Your custom Archy ISO is ready → $ISOFILE"
