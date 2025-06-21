#!/bin/bash
set -euo pipefail

# ---- CONFIG ----
DISTRO_NAME="Archy"
DISTRO_VERSION="1.0"
ARCH="amd64"
WORKDIR="$PWD/archy-build"
ISOFILE="$PWD/${DISTRO_NAME}-${DISTRO_VERSION}-${ARCH}.iso"
DEBIAN_URL="http://deb.debian.org/debian"
BUILD_DATE=$(date +%Y-%m-%d)

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

# ---- ROOT CHECK ----
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

# ---- ERROR HANDLING ----
handle_error() {
    local line="$1"
    local exit_code="$2"
    echo -e "\n\033[1;31m🛑 ERROR ON LINE $line (CODE $exit_code)\033[0m"
    echo "Attempting safe cleanup..."
    for mountpoint in $(grep "$WORKDIR" /proc/mounts | awk '{print $2}' | sort -r); do
        umount -lf "$mountpoint" 2>/dev/null && echo "Unmounted $mountpoint"
    done
    if [ -d "$WORKDIR" ]; then
        rm -rf "$WORKDIR" || echo "Could not remove $WORKDIR"
    fi
    exit "$exit_code"
}
trap 'handle_error $LINENO $?' ERR

# ---- INSTALL DEPENDENCIES ----
echo "[*] Installing required packages..."
apt-get update
apt-get install -y --fix-broken debootstrap xorriso parted dosfstools \
    grub2-common grub-efi-amd64-bin isolinux syslinux-common \
    squashfs-tools live-boot zstd locales grub-pc-bin mtools \
    debian-archive-keyring ca-certificates sudo bash nano less \
    qemu-system-x86 ovmf

# ---- WORKSPACE SETUP ----
echo "[1/6] Creating workspace..."
rm -rf "$WORKDIR" 2>/dev/null || true
mkdir -p "$WORKDIR"

# ---- BOOTSTRAP SYSTEM ----
echo "[2/6] Bootstrapping Debian unstable..."
debootstrap \
    --arch="$ARCH" \
    --variant=minbase \
    --include=systemd,linux-image-amd64,grub-efi-amd64,zstd,locales,initramfs-tools,ca-certificates \
    unstable "$WORKDIR" "$DEBIAN_URL"

# ---- MOUNT ----
for mnt in dev dev/pts proc sys run; do
    mkdir -p "$WORKDIR/$mnt"
    mount --bind "/$mnt" "$WORKDIR/$mnt"

    # Optional: Cleanly unmount on exit
    trap "umount -lf \"$WORKDIR/$mnt\" 2>/dev/null || true" EXIT

done

# ---- SYSTEM CONFIG ----
echo "[*] Configuring system..."
chroot "$WORKDIR" /bin/bash <<EOT
set -e
export DEBIAN_FRONTEND=noninteractive
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

apt-get update
apt-get install -y --allow-downgrades --fix-broken \
    systemd-sysv network-manager sudo bash nano less \
    grub-common live-boot zstd locales ca-certificates \
    live-boot-initramfs-tools

apt-get install -y --reinstall debian-archive-keyring
update-ca-certificates --fresh

# Add user
useradd -m -s /bin/bash user
usermod -aG sudo user
echo "user:archy" | chpasswd
echo "root:archy" | chpasswd

# System ID
cat > /etc/os-release <<EOF
NAME=\"Archy\"
PRETTY_NAME=\"Archy Linux\"
VERSION_ID=\"1.0\"
VERSION=\"1.0 (\$BUILD_DATE)\"
ID=archy
ID_LIKE=debian
EOF

echo "Archy 1.0 \\n \\l" > /etc/issue
cp /etc/issue /etc/issue.net
echo "Welcome to Archy Linux!" > /etc/motd

# GRUB config
mkdir -p /boot/grub
echo 'GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="Archy"
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash boot=live components"
GRUB_CMDLINE_LINUX=""' > /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg

# Initramfs
mkdir -p /etc/initramfs-tools/conf.d
echo "COMPRESS=zstd" > /etc/initramfs-tools/conf.d/compression.conf
echo "MODULES=most" > /etc/initramfs-tools/conf.d/modules.conf
update-initramfs -u -k all
EOT

# ---- UNMOUNT ----
echo "[*] Unmounting..."
for m in run dev/pts dev proc sys; do
    umount -lf "$WORKDIR/$m" 2>/dev/null || true
done

# ---- PREPARE ISO ----
echo "[5/6] Preparing ISO filesystem..."
ISO_DIR="$WORKDIR-iso"
mkdir -p "$ISO_DIR"/live "$ISO_DIR/boot/grub" "$ISO_DIR/EFI/BOOT"

VMLINUZ=$(find "$WORKDIR/boot" -name vmlinuz-* | sort -V | tail -n1)
INITRD=$(find "$WORKDIR/boot" -name initrd.img-* | sort -V | tail -n1)
cp "$VMLINUZ" "$ISO_DIR/live/vmlinuz"
cp "$INITRD" "$ISO_DIR/live/initrd.img"

mksquashfs "$WORKDIR" "$ISO_DIR/live/filesystem.squashfs" -comp zstd -e boot proc sys dev run tmp

cat > "$ISO_DIR/boot/grub/grub.cfg" <<EOF
set default=0
set timeout=5
menuentry "Archy Linux" {
    linux /live/vmlinuz boot=live components quiet splash
    initrd /live/initrd.img
}
EOF

grub-mkstandalone -O x86_64-efi -o "$ISO_DIR/EFI/BOOT/BOOTX64.EFI" \
  "boot/grub/grub.cfg=$ISO_DIR/boot/grub/grub.cfg"

cp -v /usr/lib/grub/i386-pc/boot_hybrid.img "$ISO_DIR/boot/grub/"
cp -v /usr/lib/grub/i386-pc/eltorito.img "$ISO_DIR/boot/grub/"

# ---- CREATE ISO ----
echo "[6/6] Creating hybrid ISO..."
xorriso -as mkisofs \
  -r -V "ARCHY_LIVE" \
  -J -joliet-long -l \
  -partition_offset 16 \
  -b boot/grub/eltorito.img \
     -c boot.catalog \
     -no-emul-boot -boot-load-size 4 -boot-info-table \
  --grub2-mbr /usr/lib/grub/i386-pc/boot_hybrid.img \
  -eltorito-alt-boot \
  -e EFI/BOOT/BOOTX64.EFI \
     -no-emul-boot \
  -isohybrid-gpt-basdat \
  -o "$ISOFILE" \
  "$ISO_DIR"

# ---- VERIFY ----
if [ -f "$ISOFILE" ]; then
    ISO_SIZE=$(du -h "$ISOFILE" | awk '{print $1}')
    echo -e "\n\033[1;32m✅ Archy Linux ISO created!\033[0m"
    echo -e "   File: \033[1;34m$ISOFILE\033[0m"
    echo -e "   Size: \033[1;34m$ISO_SIZE\033[0m"
    echo -e "\nTo test: \033[1;36mqemu-system-x86_64 -cdrom $ISOFILE -enable-kvm -m 2048 -smp 2\033[0m"
else
    echo -e "\n\033[1;31m❌ ISO creation failed.\033[0m"
    exit 1
fi

exit 0
