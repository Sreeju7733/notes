#!/bin/bash
set -euo pipefail

# ---- CONFIG ----
DISTRO_NAME="Archy"
DISTRO_VERSION="1.0"
ARCH="${ARCH:-amd64}"
WORKDIR="$PWD/archy-build-$ARCH"
ISOFILE="$PWD/${DISTRO_NAME}-${DISTRO_VERSION}-${ARCH}.iso"
DEBIAN_URL="http://deb.debian.org/debian"
BUILD_DATE=$(date +%Y-%m-%d)

# ---- DEPENDENCY CHECK ----
echo "[*] Checking dependencies..."
function ensure_pkg() {
    local pkg="$1" bin="$2"
    if ! command -v "$bin" &>/dev/null; then
        echo "Installing dependency: $pkg"
        sudo apt-get update
        sudo apt-get install -y "$pkg"
    fi
}
ensure_pkg debootstrap debootstrap
ensure_pkg xorriso xorriso
ensure_pkg parted parted
ensure_pkg dosfstools mkfs.fat
ensure_pkg grub2 grub-mkrescue
ensure_pkg isolinux isolinux
ensure_pkg syslinux-common isohdpfx.bin
ensure_pkg grub-efi-amd64-bin grub-mkstandalone

echo "[*] Dependencies OK"

# ---- CLEAN PREVIOUS BUILD ----
echo "[1/6] Cleaning old build directory..."
sudo rm -rf "$WORKDIR" || true

# ---- BOOTSTRAP BASE SYSTEM ----
echo "[2/6] Bootstrapping base system..."
sudo debootstrap \
    --arch="$ARCH" \
    --variant=minbase \
    --exclude=debian-faq,debian-reference,debian-installer \
    --include=apt,dpkg,linux-image-"$ARCH",systemd \
    unstable "$WORKDIR" "$DEBIAN_URL"

# ---- MOUNT SYSTEM DIRECTORIES ----
echo "[*] Mounting system directories..."
sudo mkdir -p "$WORKDIR"/{dev,proc,sys,run}
sudo mount --bind /dev "$WORKDIR/dev"
sudo mount --bind /dev/pts "$WORKDIR/dev/pts"
sudo mount -t proc proc "$WORKDIR/proc"
sudo mount -t sysfs sys "$WORKDIR/sys"
sudo mount -t tmpfs tmpfs "$WORKDIR/run"

# ---- CUSTOMIZE CHROOT ----
echo "[3/6] Customizing system in chroot..."
sudo chroot "$WORKDIR" /bin/bash <<EOF
set -e
export DEBIAN_FRONTEND=noninteractive

# Basic system setup
echo "archy" > /etc/hostname
echo "127.0.1.1 archy" >> /etc/hosts

# Install core packages
apt-get update
apt-get install -y --no-install-recommends \
    systemd-sysv linux-image-"$ARCH" grub-pc grub-efi-amd64 \
    network-manager sudo bash nano less locales

# Clean up
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Create user
useradd -m -s /bin/bash user
echo "user:archy" | chpasswd
echo "root:archy" | chpasswd
EOF

# ---- UNMOUNT SYSTEM DIRECTORIES ----
echo "[4/6] Unmounting system directories..."
sudo umount -R "$WORKDIR/dev/pts"
sudo umount -R "$WORKDIR/dev"
sudo umount -R "$WORKDIR/proc"
sudo umount -R "$WORKDIR/sys"
sudo umount -R "$WORKDIR/run"

# ---- CREATE ISO DIRECTORY STRUCTURE ----
echo "[5/6] Creating ISO structure..."
ISO_DIR="$WORKDIR/iso"
sudo mkdir -p "$ISO_DIR"/{boot/grub,live}

# Copy kernel and initrd
sudo cp "$WORKDIR"/boot/vmlinuz-* "$ISO_DIR/live/vmlinuz"
sudo cp "$WORKDIR"/boot/initrd.img-* "$ISO_DIR/live/initrd.img"

# Create GRUB config
sudo cat > "$WORKDIR/boot/grub/grub.cfg" <<EOF
set default=0
set timeout=30

menuentry "Archy Linux" {
    linux /live/vmlinuz boot=live components quiet splash
    initrd /live/initrd.img
}
EOF

# Create ISO
echo "[6/6] Generating ISO image..."
sudo grub-mkrescue -o "$ISOFILE" "$ISO_DIR" --volid="ARCHY_LIVE"

# ---- CLEAN UP ----
sudo rm -rf "$WORKDIR"
echo -e "\n\033[1;32m✅ Successfully created Archy Linux ISO: $ISOFILE\033[0m"
echo -e "Test with: \033[1;36mqemu-system-x86_64 -cdrom \"$ISOFILE\" -m 2G\033[0m\n"
