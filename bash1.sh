#!/bin/bash
set -euo pipefail

# ---- CONFIG ----
DISTRO_NAME="Archy"
DISTRO_VERSION="1.0"
ARCH="amd64"
WORKDIR="/archy-build"
ISOFILE="${DISTRO_NAME}-${DISTRO_VERSION}-${ARCH}.iso"
DEBIAN_URL="http://deb.debian.org/debian"
BUILD_DATE=$(date +%Y-%m-%d)

# Ensure PATH includes standard locations
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

# ---- ERROR HANDLING ----
handle_error() {
    local line="$1"
    local exit_code="$2"
    echo -e "\n\033[1;31m🛑 CRITICAL ERROR ON LINE $line (CODE $exit_code)\033[0m"
    echo "Possible causes:"
    echo "1. Package conflicts"
    echo "2. Mount point issues"
    echo "3. Permission problems"
    echo "4. Missing dependencies"
    echo -e "\nAttempting safe cleanup..."
    
    # Force unmount everything
    for mountpoint in $(grep "$WORKDIR" /proc/mounts | awk '{print $2}' | sort -r); do
        umount -lf "$mountpoint" 2>/dev/null && echo "Unmounted $mountpoint" || true
    done
    
    # Remove workdir if possible
    [ -d "$WORKDIR" ] && rm -rf "$WORKDIR" || echo "Could not remove $WORKDIR"
    
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

# Verify debootstrap installation
if ! command -v debootstrap >/dev/null; then
    echo "debootstrap not found! Trying alternative paths..."
    # Check common locations
    if [ -f "/usr/sbin/debootstrap" ]; then
        ln -s /usr/sbin/debootstrap /usr/bin/debootstrap
    else
        echo "FATAL: debootstrap not found in any standard location"
        exit 1
    fi
fi

# ---- WORKSPACE SETUP ----
echo "[1/6] Creating workspace..."
rm -rf "$WORKDIR" 2>/dev/null || true
mkdir -p "$WORKDIR"
cd "$WORKDIR"

# ---- BOOTSTRAP SYSTEM ----
echo "[2/6] Bootstrapping Debian unstable..."
debootstrap \
    --arch="$ARCH" \
    --variant=minbase \
    --include=systemd,linux-image-amd64,grub-efi-amd64,zstd,locales,initramfs-tools,ca-certificates \
    unstable "$WORKDIR" "$DEBIAN_URL"

# ---- MOUNT HANDLING ----
mount_safe() {
    local target="$1"
    local src="${2:-/${target##*/}}"
    echo "Mounting $src to $target"
    mkdir -p "$target"
    mount --bind "$src" "$target" 2>/dev/null || true
}

mount_safe "$WORKDIR/dev"
mount_safe "$WORKDIR/proc"
mount_safe "$WORKDIR/sys"
mount_safe "$WORKDIR/dev/pts" "/dev/pts"
mount_safe "$WORKDIR/run"

# ---- SYSTEM CONFIGURATION ----
echo "[3/6] Configuring system..."
chroot "$WORKDIR" /bin/bash <<'EOT'
set -e

# Safe environment setup
export DEBIAN_FRONTEND=noninteractive
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

# Ensure critical directories exist
mkdir -p /etc/default /boot/grub /usr/bin /lib/live/config

# Package installation
apt-get update
apt-get install -y --no-install-recommends \
    systemd-sysv network-manager sudo bash nano less \
    grub-common live-boot zstd locales ca-certificates \
    live-boot-initramfs-tools

# Keyring maintenance
apt-get install -y --reinstall debian-archive-keyring

# Certificate update
update-ca-certificates --fresh

# System identity
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

# User setup
useradd -m -s /bin/bash user
echo "user:archy" | chpasswd
echo "root:archy" | chpasswd

# Safe GRUB configuration
mkdir -p /boot/grub
cat > /etc/default/grub <<EOF
GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="Archy"
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"
GRUB_CMDLINE_LINUX="boot=live components"
EOF
grub-mkconfig -o /boot/grub/grub.cfg

# Initramfs configuration
mkdir -p /etc/initramfs-tools/conf.d
echo "COMPRESS=zstd" > /etc/initramfs-tools/conf.d/compression.conf
echo "MODULES=most" > /etc/initramfs-tools/conf.d/modules.conf
update-initramfs -u -k all

# Live environment setup
cat > /lib/live/config/0030-archy <<'EOF'
#!/bin/sh
echo "archy-live" > /etc/hostname
cat > /etc/motd <<'MOTD'
Welcome to Archy Linux - The Minimalist's Dream
Type 'archy-help' for basic commands
MOTD
EOF
chmod +x /lib/live/config/0030-archy

# Custom utilities
cat > /usr/bin/archy-help <<'EOF'
#!/bin/bash
echo -e "\033[1;36mArchy Help System\033[0m"
echo "archy-install - Install Archy to disk"
echo "archy-upgrade - Update the system"
echo "archy-init    - First-time setup"
echo "au            - Alias for archy-upgrade"
echo "ai <pkg>      - Install package"
echo "ar <pkg>      - Remove package"
echo "as <term>     - Search packages"
EOF
chmod +x /usr/bin/archy-help

# Installer script (simplified version)
cat > /usr/bin/archy-install <<'EOF'
#!/bin/bash
set -e
echo -e "\033[1;36mArchy Installer\033[0m"
[ $(id -u) -eq 0 ] || { echo "Run as root"; exit 1; }

echo "1) Auto install (GPT/UEFI)"
echo "2) Manual partitioning"
read -p "Select option [1/2]: " OPT

case $OPT in
    1)
        lsblk -d -o NAME,SIZE,MODEL
        read -p "Enter target disk (e.g. sda): " DISK
        DISK="/dev/$DISK"

        parted -s "$DISK" mklabel gpt
        parted -s "$DISK" mkpart ESP 1MiB 513MiB
        parted -s "$DISK" set 1 esp on
        parted -s "$DISK" mkpart root 513MiB 100%
        
        mkfs.fat -F32 "${DISK}1"
        mkfs.ext4 -F "${DISK}2"
        
        mount "${DISK}2" /mnt
        mkdir -p /mnt/boot/efi
        mount "${DISK}1" /mnt/boot/efi
        
        # Copy live system to disk
        cp -ax / /mnt
        ;;
    2) 
        echo "Manual installation not implemented in this version"
        exit 1
        ;;
    *) 
        echo "Invalid option"
        exit 1
        ;;
esac

# Chroot setup
mount --bind /dev /mnt/dev
mount --bind /proc /mnt/proc
mount --bind /sys /mnt/sys

chroot /mnt /bin/bash <<'INSTALL'
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Archy
update-grub
passwd -d root
echo "Installation complete! Unmount and reboot."
INSTALL

umount /mnt/dev
umount /mnt/proc
umount /mnt/sys
umount /mnt/boot/efi
umount /mnt
EOF
chmod +x /usr/bin/archy-install
EOT

# ---- ISO PREPARATION ----
echo "[4/6] Preparing ISO filesystem..."
ISO_DIR="$WORKDIR/iso"
mkdir -p "$ISO_DIR"/{live,boot/grub,EFI/BOOT}

# Find latest kernel and initrd
VMLINUZ=$(find "$WORKDIR/boot" -name vmlinuz-* ! -name '*-rescue*' | sort -V | tail -n1)
INITRD=$(find "$WORKDIR/boot" -name initrd.img-* ! -name '*-rescue*' | sort -V | tail -n1)

[ -f "$VMLINUZ" ] && cp -v "$VMLINUZ" "$ISO_DIR/live/vmlinuz"
[ -f "$INITRD" ] && cp -v "$INITRD" "$ISO_DIR/live/initrd.img"

# Create squashfs filesystem
echo "Creating filesystem.squashfs..."
mksquashfs "$WORKDIR" "$ISO_DIR/live/filesystem.squashfs" -comp zstd -e boot

# GRUB configuration
cat > "$ISO_DIR/boot/grub/grub.cfg" <<EOF
set default=0
set timeout=5
menuentry "Archy Linux" {
    linux /live/vmlinuz boot=live components quiet splash
    initrd /live/initrd.img
}
EOF

# EFI boot setup
grub-mkstandalone -O x86_64-efi -o "$ISO_DIR/EFI/BOOT/BOOTX64.EFI" "boot/grub/grub.cfg=$ISO_DIR/boot/grub/grub.cfg"

# BIOS boot setup
mkdir -p "$ISO_DIR/boot/grub/i386-pc"
cp -v /usr/lib/grub/i386-pc/{boot.img,core.img,cdboot.img} "$ISO_DIR/boot/grub/i386-pc/"

# ---- ISO CREATION ----
echo "[5/6] Creating hybrid ISO..."
xorriso -as mkisofs \
  -volid "ARCHY_LIVE" \
  -o "$ISOFILE" \
  -r -J -joliet-long \
  -iso-level 3 \
  -partition_offset 16 \
  --grub2-mbr /usr/lib/grub/i386-pc/boot.img \
  --mbr-force-bootable \
  -append_partition 2 0xEF "$ISO_DIR/EFI/BOOT/BOOTX64.EFI" \
  -appended_part_as_gpt \
  -c boot.catalog \
  -b boot/grub/i386-pc/cdboot.img \
  -no-emul-boot -boot-load-size 4 -boot-info-table \
  -eltorito-alt-boot \
  -e '--interval:appended_partition_2:all::' \
  -no-emul-boot \
  -isohybrid-gpt-basdat \
  "$ISO_DIR"

# ---- SAFE CLEANUP ----
echo "[6/6] Performing safe cleanup..."
for mountpoint in dev/pts dev proc sys run; do
    umount -lf "$WORKDIR/$mountpoint" 2>/dev/null || true
done

# ---- VERIFICATION ----
[ -f "$ISOFILE" ] && {
    ISO_SIZE=$(du -h "$ISOFILE" | awk '{print $1}')
    echo -e "\n\033[1;32m✅ Archy Linux ISO successfully created!\033[0m"
    echo -e "   Location: \033[1;34m$(pwd)/$ISOFILE\033[0m"
    echo -e "   Size: \033[1;34m$ISO_SIZE\033[0m"
    echo -e "\nTest with: \033[1;36mqemu-system-x86_64 -cdrom \"$ISOFILE\" -m 2G\033[0m"
} || {
    echo -e "\n\033[1;31m❌ ISO creation failed. See errors above.\033[0m"
    exit 1
}

exit 0
