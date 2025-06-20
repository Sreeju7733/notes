#!/bin/bash
set -euo pipefail

# ---- CONFIG ----
DISTRO_NAME="Archy"
DISTRO_VERSION="1.0"
ARCH="${ARCH:-amd64}"
WORKDIR="/archy-build"
ISOFILE="/${DISTRO_NAME}-${DISTRO_VERSION}-${ARCH}.iso"
DEBIAN_URL="http://deb.debian.org/debian"
BUILD_DATE=$(date +%Y-%m-%d)

# ---- TERMINAL AND LOCALE SETUP ----
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
mkdir -p /dev/pts
mount -t devpts devpts /dev/pts 2>/dev/null || true

# ---- DEPENDENCY INSTALLATION ----
echo "[*] Installing required packages..."
apt-get update
apt-get install -y debootstrap xorriso parted dosfstools \
    grub2-common grub-efi-amd64-bin isolinux syslinux-common \
    squashfs-tools live-boot zstd locales

# Configure locales
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen en_US.UTF-8
update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

# ---- CLEAN PREVIOUS BUILD ----
echo "[1/6] Cleaning workspace..."
umount -R "$WORKDIR" 2>/dev/null || true
rm -rf "$WORKDIR" "$ISOFILE" 2>/dev/null || true
mkdir -p "$WORKDIR"

# ---- BOOTSTRAP BASE SYSTEM ----
echo "[2/6] Bootstrapping Debian unstable..."
debootstrap \
    --arch="$ARCH" \
    --variant=minbase \
    --include=systemd,linux-image-$ARCH,grub-efi-amd64,zstd,locales,initramfs-tools \
    unstable "$WORKDIR" "$DEBIAN_URL"

# ---- MOUNT SYSTEM DIRECTORIES ----
echo "[*] Mounting system directories..."
mount --bind /dev "$WORKDIR/dev"
mount -t proc proc "$WORKDIR/proc"
mount -t sysfs sys "$WORKDIR/sys"
mount -t devpts devpts "$WORKDIR/dev/pts"
mount -t tmpfs tmpfs "$WORKDIR/run"

# ---- SYSTEM CONFIGURATION ----
echo "[3/6] Configuring system..."
chroot "$WORKDIR" /bin/bash <<'EOT'
set -e

# Set locale environment
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# Basic system setup
echo "archy" > /etc/hostname
echo "127.0.1.1 archy" >> /etc/hosts

# Install essential packages
apt-get update
apt-get install -y --no-install-recommends \
    systemd-sysv network-manager sudo \
    bash nano less grub-common live-boot zstd locales

# Configure locales
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen en_US.UTF-8
update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

# Create user
useradd -m -s /bin/bash user
echo "user:archy" | chpasswd
echo "root:archy" | chpasswd

# OS identity
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

# Custom scripts
cat > /usr/bin/archy-help <<'EOF'
#!/bin/bash
echo -e "\033[1;36mArchy Help System\033[0m"
echo "archy-install   - Install Archy to disk"
echo "archy-upgrade   - Update the system"
echo "archy-init      - First-time setup"
echo "au              - Update system (alias)"
echo "ai <pkg>        - Install package"
echo "ar <pkg>        - Remove package"
echo "as <term>       - Search packages"
EOF
chmod +x /usr/bin/archy-help

# Installer script
cat > /usr/bin/archy-install <<'EOF'
#!/bin/bash
set -e
echo -e "\033[1;36mArchy Installer\033[0m"
[ "$(id -u)" -eq 0 ] || { echo "Run as root"; exit 1; }

lsblk -d -o NAME,SIZE,MODEL
read -p "Enter target disk (e.g. sda): " DISK
DISK="/dev/$DISK"

echo "1) Auto install (GPT/UEFI)"
echo "2) Manual partitioning"
read -p "Select option [1/2]: " OPT

case $OPT in
    1)
        parted -s "$DISK" mklabel gpt
        parted -s "$DISK" mkpart ESP 1MiB 513MiB
        parted -s "$DISK" set 1 esp on
        parted -s "$DISK" mkpart root 513MiB 100%
        
        mkfs.fat -F32 "${DISK}1"
        mkfs.ext4 -F "${DISK}2"
        
        mount "${DISK}2" /mnt
        mkdir -p /mnt/boot/efi
        mount "${DISK}1" /mnt/boot/efi
        ;;
    2) 
        cfdisk "$DISK"
        echo "Mount partitions manually and re-run"
        exit
        ;;
    *) 
        echo "Invalid option"
        exit 1
        ;;
esac

# Install system
debootstrap unstable /mnt "$DEBIAN_URL"
arch-chroot /mnt /bin/bash <<'INSTALL'
apt-get update
apt-get install -y linux-image-amd64 grub-efi-amd64 sudo network-manager
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Archy
update-grub
useradd -m -s /bin/bash user
echo "user:archy" | chpasswd
echo "root:archy" | chpasswd
systemctl enable NetworkManager
INSTALL

echo "Installation complete! Unmount and reboot."
EOF
chmod +x /usr/bin/archy-install

# Setup GRUB properly
mkdir -p /boot/grub
cat > /etc/default/grub <<EOF
GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="Archy"
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"
GRUB_CMDLINE_LINUX=""
EOF

# Force device detection for GRUB
cat > /usr/bin/fake-grub-probe <<'EOF'
#!/bin/bash
echo "(hd0,msdos1)"
EOF
chmod +x /usr/bin/fake-grub-probe

mv /usr/sbin/grub-probe /usr/sbin/grub-probe-real
ln -s /usr/bin/fake-grub-probe /usr/sbin/grub-probe

update-grub

# Restore original grub-probe
rm /usr/sbin/grub-probe
mv /usr/sbin/grub-probe-real /usr/sbin/grub-probe
EOT

# ---- INITRAMFS CONFIGURATION ----
echo "[4/6] Configuring initramfs..."
chroot "$WORKDIR" /bin/bash <<'EOT'
# Set compression to zstd
echo "COMPRESS=zstd" > /etc/initramfs-tools/conf.d/compression.conf

# Use MODULES=most to prevent device detection failures
echo "MODULES=most" > /etc/initramfs-tools/conf.d/modules.conf

# Disable device mapper verification
echo "DEVICE_MAPPER=no" > /etc/initramfs-tools/conf.d/dm.conf

# Update initramfs with workaround
update-initramfs -u -k all
EOT

# ---- PREPARE LIVE SYSTEM ----
echo "[5/6] Preparing live environment..."
chroot "$WORKDIR" /bin/bash <<'EOT'
# Create necessary directories for live-boot
mkdir -p /lib/live/config

# Create live-boot configuration
cat > /lib/live/config/0030-archy <<'EOF'
#!/bin/sh

set -e

# Set hostname
echo "archy-live" > /etc/hostname

# Custom motd
cat > /etc/motd <<'MOTD'
Welcome to Archy Linux - The Minimalist's Dream
Type 'archy-help' for basic commands
MOTD
EOF
chmod +x /lib/live/config/0030-archy
EOT

# ---- CREATE ISO STRUCTURE ----
echo "[6/6] Creating ISO filesystem..."
ISO_DIR="$WORKDIR/iso"
mkdir -p "$ISO_DIR"/{live,boot/grub}

# Copy kernel and initrd
VMLINUZ=$(find "$WORKDIR/boot" -name vmlinuz-* -print -quit)
INITRD=$(find "$WORKDIR/boot" -name initrd.img-* -print -quit)

if [ -f "$VMLINUZ" ]; then
    cp -v "$VMLINUZ" "$ISO_DIR/live/vmlinuz"
else
    echo "⚠️ Warning: vmlinuz not found in $WORKDIR/boot"
fi

if [ -f "$INITRD" ]; then
    cp -v "$INITRD" "$ISO_DIR/live/initrd.img"
else
    echo "⚠️ Warning: initrd.img not found in $WORKDIR/boot"
fi

# Create GRUB configuration
cat > "$ISO_DIR/boot/grub/grub.cfg" <<'EOF'
set default=0
set timeout=5

menuentry "Archy Linux (Live)" {
    linux /live/vmlinuz boot=live components quiet splash
    initrd /live/initrd.img
}

menuentry "Archy Linux (Install)" {
    linux /live/vmlinuz boot=live components quiet splash --
    initrd /live/initrd.img
}
EOF

# Create EFI boot image
echo "[+] Creating EFI boot image..."
mkdir -p "$ISO_DIR/EFI/BOOT"
grub-mkstandalone -O x86_64-efi -o "$ISO_DIR/EFI/BOOT/BOOTX64.EFI" "boot/grub/grub.cfg=$ISO_DIR/boot/grub/grub.cfg"

# Create bootable ISO using reliable method
echo "[*] Generating ISO image..."
xorriso -as mkisofs \
  -r -V "ARCHY_LIVE" \
  -o "$ISOFILE" \
  -J -joliet-long \
  -iso-level 3 \
  -partition_offset 16 \
  --grub2-mbr /usr/share/grub/grub-mkconfig_lib \
  --mbr-force-bootable \
  -append_partition 2 0xEF "$ISO_DIR/EFI/BOOT/BOOTX64.EFI" \
  -appended_part_as_gpt \
  -c boot.catalog \
  -b boot/grub/i386-pc/eltorito.img \
  -no-emul-boot -boot-load-size 4 -boot-info-table \
  -eltorito-alt-boot \
  -e '--interval:appended_partition_2:all::' \
  -no-emul-boot \
  "$ISO_DIR"

# ---- FINAL CLEANUP ----
echo "[*] Cleaning up build environment..."
{
    umount -R "$WORKDIR" 2>/dev/null || true
    rm -rf "$WORKDIR"
} && echo "✅ Cleanup complete!"

# ---- VERIFICATION ----
if [ -f "$ISOFILE" ]; then
    ISO_SIZE=$(du -h "$ISOFILE" | cut -f1)
    echo -e "\n\033[1;32m🎉 Successfully created Archy Linux ISO!\033[0m"
    echo -e "   File: \033[1;34m$ISOFILE\033[0m"
    echo -e "   Size: \033[1;34m$ISO_SIZE\033[0m"
    echo -e "\n💡 Test with: \033[1;36mqemu-system-x86_64 -cdrom \"$ISOFILE\" -m 2G\033[0m"
else
    echo -e "\n\033[1;31m❌ ISO creation failed. Check output for errors.\033[0m"
    exit 1
fi
