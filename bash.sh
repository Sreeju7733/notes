#!/bin/bash
set -euo pipefail

# === Config ===
export DISTRO_NAME="Archy"
export ARCH="amd64"
export RELEASE="sid"
export MIRROR="http://deb.debian.org/debian"
export WORKDIR="$PWD/archy-build"
export CHROOT="$WORKDIR/chroot"
export ISOFILE="$PWD/${DISTRO_NAME}.iso"

# === Clean Previous Build ===
sudo rm -rf "$WORKDIR"
mkdir -p "$CHROOT"

# === Step 1: Bootstrap Debian Sid ===
sudo debootstrap --arch="$ARCH" "$RELEASE" "$CHROOT" "$MIRROR"

# === Step 2: Chroot Configuration ===
sudo cp /etc/resolv.conf "$CHROOT/etc/"
sudo mount --bind /dev "$CHROOT/dev"
sudo mount --bind /proc "$CHROOT/proc"
sudo mount --bind /sys "$CHROOT/sys"

sudo chroot "$CHROOT" /bin/bash <<'EOL'

set -euo pipefail

echo "[*] Setting hostname and sources"
echo "archy" > /etc/hostname

cat > /etc/apt/sources.list <<EOF
deb http://deb.debian.org/debian sid main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security sid-security main
EOF

apt update
apt -y install locales
locale-gen en_US.UTF-8
export LANG=en_US.UTF-8

echo "[*] Installing base packages"
apt install -y \
    systemd systemd-sysv grub-pc linux-image-amd64 \
    sudo net-tools iputils-ping ifupdown isc-dhcp-client \
    ca-certificates curl wget gnupg vim bash-completion \
    live-boot live-config live-build

echo "[*] Creating user"
useradd -m -s /bin/bash archy
echo "archy:archy" | chpasswd
usermod -aG sudo archy

echo "[*] Debranding Debian → Archy"
for file in $(find /etc /usr/share -type f -exec grep -Il 'Debian' {} \;); do
  sed -i 's/Debian/Archy/g' "$file" || true
done

EOL

# === Step 3: Unmount
sudo umount "$CHROOT/dev" || true
sudo umount "$CHROOT/proc" || true
sudo umount "$CHROOT/sys" || true

# === Step 4: ISO Generation ===
echo "[*] Building ISO"
mkdir -p "$WORKDIR/iso"
cd "$WORKDIR"

cat > auto.conf <<EOF
LB_DISTRIBUTION="$RELEASE"
LB_ARCHITECTURES="$ARCH"
LB_MODE="debian"
LB_LINUX_FLAVOURS="amd64"
LB_INITRAMFS="live-boot"
LB_ARCHIVE_AREAS="main contrib non-free non-free-firmware"
LB_MIRROR_BOOTSTRAP="$MIRROR"
LB_MIRROR_CHROOT="$MIRROR"
LB_MIRROR_BINARY="$MIRROR"
LB_IMAGE_NAME="$DISTRO_NAME"
LB_ISO_VOLUME="$DISTRO_NAME Live"
EOF

sudo lb config
sudo lb build

# === Rename ISO
mv live-image-amd64.hybrid.iso "$ISOFILE"
echo "✅ ISO Build Complete: $ISOFILE"
