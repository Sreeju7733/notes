#!/bin/bash
set -euo pipefail

# ---- CONFIG ----
DISTRO_NAME="Archy"
DISTRO_VERSION="1.0"
ARCH="${ARCH:-amd64}"
WORKDIR="/archy-build"  # Using absolute path to avoid permission issues
ISOFILE="/${DISTRO_NAME}-${DISTRO_VERSION}-${ARCH}.iso"
DEBIAN_URL="http://deb.debian.org/debian"
BUILD_DATE=$(date +%Y-%m-%d)

# ---- TERMINAL SETUP ----
# Ensure terminal devices exist for sudo operations
mkdir -p /dev/pts
mount -t devpts devpts /dev/pts 2>/dev/null || true

# ---- DEPENDENCY INSTALLATION ----
echo "[*] Installing required packages..."
{
    apt-get update
    apt-get install -y debootstrap xorriso parted dosfstools \
        grub2-common grub-efi-amd64-bin isolinux syslinux-common \
        squashfs-tools live-boot
} >/dev/null 2>&1

# ---- CLEAN PREVIOUS BUILD ----
echo "[1/6] Cleaning workspace..."
umount -l $WORKDIR/dev/* 2>/dev/null || true
rm -rf "$WORKDIR" "$ISOFILE" 2>/dev/null || true
mkdir -p "$WORKDIR"

# ---- BOOTSTRAP BASE SYSTEM ----
echo "[2/6] Bootstrapping Debian unstable..."
debootstrap \
    --arch="$ARCH" \
    --variant=minbase \
    --include=systemd,linux-image-$ARCH,grub-efi-amd64 \
    unstable "$WORKDIR" "$DEBIAN_URL" 2>/dev/null

# ---- MOUNT SYSTEM DIRECTORIES ----
echo "[*] Mounting system directories..."
mount --bind /dev "$WORKDIR/dev"
mount -t proc proc "$WORKDIR/proc"
mount -t sysfs sys "$WORKDIR/sys"
mount -t devpts devpts "$WORKDIR/dev/pts"

# ---- SYSTEM CONFIGURATION ----
echo "[3/6] Configuring system..."
chroot "$WORKDIR" /bin/bash <<'EOT'
set -e

# Basic system setup
echo "archy" > /etc/hostname
echo "127.0.1.1 archy" >> /etc/hosts

# Install essential packages
apt-get update
apt-get install -y --no-install-recommends \
    systemd-sysv initramfs-tools network-manager sudo \
    locales bash nano less grub-common live-boot

# Create user
useradd -m -s /bin/bash user
echo "user:archy" | chpasswd
echo "root:archy" | chpasswd

# Configure locales
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
update-locale LANG=en_US.UTF-8

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

update-grub
EOT

# ---- PREPARE LIVE SYSTEM ----
echo "[4/6] Preparing live environment..."
chroot "$WORKDIR" /bin/bash <<'EOT'
# Create live-boot configuration
mkdir -p /lib/live/mount
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

# Update initramfs
update-initramfs -u
EOT

# ---- CREATE ISO STRUCTURE ----
echo "[5/6] Creating ISO filesystem..."
ISO_DIR="$WORKDIR/iso"
mkdir -p "$ISO_DIR"/{live,boot/grub}

# Copy kernel and initrd
VMLINUZ=$(find "$WORKDIR/boot" -name vmlinuz-* -print -quit)
INITRD=$(find "$WORKDIR/boot" -name initrd.img-* -print -quit)
[ -n "$VMLINUZ" ] && cp "$VMLINUZ" "$ISO_DIR/live/vmlinuz"
[ -n "$INITRD" ] && cp "$INITRD" "$ISO_DIR/live/initrd.img"

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

# ---- BUILD ISO ----
echo "[6/6] Generating ISO image..."
grub-mkrescue -o "$ISOFILE" "$ISO_DIR" --volid="ARCHY_LIVE" 2>/dev/null

# ---- CLEANUP ----
umount -R "$WORKDIR" 2>/dev/null || true
rm -rf "$WORKDIR"

echo -e "\n\033[1;32m✅ Successfully created: $ISOFILE\033[0m"
echo -e "Test with: \033[1;36mqemu-system-x86_64 -cdrom \"$ISOFILE\" -m 2G\033[0m"
