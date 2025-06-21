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

# ---- DEPENDENCY INSTALLATION ----
echo "[*] Installing required packages..."
apt-get update
apt-get install -y --fix-broken debootstrap xorriso parted dosfstools \
    grub2-common grub-efi-amd64-bin isolinux syslinux-common \
    squashfs-tools live-boot zstd locales grub-pc-bin mtools \
    debian-archive-keyring ca-certificates

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

# ---- MOUNT HANDLING ----
for mnt in dev dev/pts proc sys run; do
    mkdir -p "$WORKDIR/$mnt"
    mount --bind "/$mnt" "$WORKDIR/$mnt"
done

# ---- SYSTEM CONFIGURATION ----
echo "[*] Setting user/root passwords..."
chroot "$WORKDIR" /bin/bash -c "
useradd -m -s /bin/bash user
echo 'user:archy' | chpasswd
echo 'root:archy' | chpasswd
"

echo "[3/6] Configuring system..."
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

cat > /etc/os-release <<EOF
NAME="Archy"
PRETTY_NAME="Archy Linux"
VERSION_ID="1.0"
VERSION="1.0 ($BUILD_DATE)"
ID=archy
ID_LIKE=debian
HOME_URL="https://archy.org"
SUPPORT_URL="https://archy.org/support"
BUG_REPORT_URL="https://archy.org/bugs"
EOF

echo "Archy 1.0 \\n \\l" > /etc/issue
cp /etc/issue /etc/issue.net

echo "Welcome to Archy - The Minimalist's Dream" > /etc/motd

cat > /etc/default/grub <<EOF
GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="Archy"
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash boot=live components"
GRUB_CMDLINE_LINUX=""
EOF
grub-mkconfig -o /boot/grub/grub.cfg

mkdir -p /etc/initramfs-tools/conf.d
echo "COMPRESS=zstd" > /etc/initramfs-tools/conf.d/compression.conf
echo "MODULES=most" > /etc/initramfs-tools/conf.d/modules.conf
update-initramfs -u -k all
EOT

# ---- CLEANUP BEFORE SQUASHFS ----
echo "[4/6] Cleaning up mounts..."
for m in run dev/pts dev proc sys; do
    umount -lf "$WORKDIR/$m" 2>/dev/null || true
done

# ---- ISO PREPARATION ----
echo "[5/6] Preparing ISO filesystem..."
ISO_DIR="$WORKDIR-iso"
mkdir -p "$ISO_DIR"/live
mkdir -p "$ISO_DIR/boot/grub/i386-pc"
mkdir -p "$ISO_DIR/EFI/BOOT"

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

cp /usr/lib/grub/i386-pc/* "$ISO_DIR/boot/grub/i386-pc/"
cp /usr/lib/ISOLINUX/isohdpfx.bin "$ISO_DIR/isohdpfx.bin"

# ---- ISO CREATION ----
echo "[6/6] Creating hybrid ISO..."
xorriso -as mkisofs \
  -volid "ARCHY_LIVE" \
  -o "$ISOFILE" \
  -isohybrid-mbr "$ISO_DIR/isohdpfx.bin" \
  -c boot/boot.cat \
  -b boot/grub/i386-pc/eltorito.img \
     -no-emul-boot -boot-load-size 4 -boot-info-table \
  -eltorito-alt-boot \
  -e EFI/BOOT/BOOTX64.EFI \
     -no-emul-boot \
  -isohybrid-gpt-basdat \
  -r -J -joliet-long \
  "$ISO_DIR"

# ---- DONE ----
if [ -f "$ISOFILE" ]; then
    ISO_SIZE=$(du -h "$ISOFILE" | awk '{print $1}')
    echo -e "\n\033[1;32m✅ Archy Linux ISO created!\033[0m"
    echo -e "   File: \033[1;34m$ISOFILE\033[0m"
    echo -e "   Size: \033[1;34m$ISO_SIZE\033[0m"
else
    echo -e "\n\033[1;31m❌ ISO creation failed.\033[0m"
    exit 1
fi

exit 0
