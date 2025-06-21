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

echo "[*] Cleaning previous build"
sudo rm -rf "$WORKDIR"
mkdir -p "$CHROOT"

echo "[*] Bootstrapping Debian Sid base system"
sudo debootstrap --arch="$ARCH" "$RELEASE" "$CHROOT" "$MIRROR"

echo "[*] Mounting special filesystems for chroot"
sudo cp /etc/resolv.conf "$CHROOT/etc/"
sudo mount --bind /dev "$CHROOT/dev"
sudo mount --bind /proc "$CHROOT/proc"
sudo mount --bind /sys "$CHROOT/sys"

echo "[*] Entering chroot and configuring system..."
sudo chroot "$CHROOT" /bin/bash <<'EOL'
set -euo pipefail

echo "archy" > /etc/hostname

# Add ONLY the Sid main repo (rolling updates)
cat > /etc/apt/sources.list <<EOF
deb http://deb.debian.org/debian sid main contrib non-free non-free-firmware
EOF

apt update
apt -y install locales
locale-gen en_US.UTF-8
export LANG=en_US.UTF-8

echo "[*] Installing essential packages"
apt install -y \
    systemd systemd-sysv grub-pc linux-image-amd64 \
    sudo net-tools iputils-ping ifupdown isc-dhcp-client \
    ca-certificates curl wget gnupg vim bash-completion \
    live-boot live-config live-build

echo "[*] Creating user: archy"
useradd -m -s /bin/bash archy
echo "archy:archy" | chpasswd
usermod -aG sudo archy

echo "[*] Debranding Debian to Archy..."
for file in $(find /etc /usr/share -type f -exec grep -Il 'Debian' {} \; 2>/dev/null); do
  sed -i 's/Debian/Archy/g' "$file" || true
done

EOL

echo "[*] Unmounting filesystems"
sudo umount "$CHROOT/dev" || true
sudo umount "$CHROOT/proc" || true
sudo umount "$CHROOT/sys" || true

echo "[*] Setting up ISO build environment"
cd "$WORKDIR"
sudo lb config noauto \
    --distribution "$RELEASE" \
    --architecture "$ARCH" \
    --debian-installer live \
    --archive-areas "main contrib non-free non-free-firmware" \
    --bootappend-live "boot=live components username=archy hostname=archy" \
    --binary-images iso-hybrid \
    --mirror-bootstrap "$MIRROR" \
    --mirror-chroot "$MIRROR" \
    --mirror-binary "$MIRROR" \
    --linux-flavours amd64 \
    --iso-volume "Archy Live" \
    --iso-application "Archy OS"

echo "[*] Building ISO (this might take a while)"
sudo lb build

echo "[*] Moving ISO to project root"
mv live-image-amd64.hybrid.iso "$ISOFILE"

echo "✅ Archy ISO ready: $ISOFILE"
