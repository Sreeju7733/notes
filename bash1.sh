#!/bin/bash
set -euo pipefail

# === Config ===
export DISTRO_NAME="Archy"
export DISTRO_VERSION="1.0"
export ARCH="${ARCH:-amd64}"
export WORKDIR="$PWD/archy-build-$ARCH"
export ISOFILE="$PWD/${DISTRO_NAME}-${DISTRO_VERSION}-$ARCH.iso"
export DEBIAN_URL="http://deb.debian.org/debian"
export BUILD_DATE=$(date +%Y-%m-%d)

# === Clean old build ===
echo "[1/6] 🧹 Cleaning old build..."
sudo rm -rf "$WORKDIR"

# === Create minimal base ===
echo "[2/6] 🏗️  Creating minimal base system..."
sudo debootstrap \
    --arch="$ARCH" \
    --variant=minbase \
    --exclude=debian-archive-keyring,debian-faq,debian-reference,debian-installer \
    --include=apt,dpkg,linux-image-$ARCH,systemd \
    unstable "$WORKDIR" "$DEBIAN_URL"

# === Chroot system customization ===
echo "[3/6] 🎨 Customizing Archy system..."
sudo chroot "$WORKDIR" /bin/bash <<'EOF'
set -e

# Remove Debian branding and docs
echo "  Removing Debian branding..."
apt purge -y debian-* os-prober tasksel reportbug || true
rm -rf /usr/share/{doc,man,doc-base,common-licenses,debian*}
rm -rf /etc/{network,default,init.d,rc*.d,dpkg,apt/apt.conf.d}
rm -f /etc/{issue,issue.net,os-release,motd,legal}

# Base packages
echo "  Installing base packages..."
apt update
apt install -y --no-install-recommends \
    bash coreutils systemd udev sudo nano less grub2 \
    network-manager wget curl fdisk parted locales \
    apt-listbugs xorriso isolinux syslinux-common

# Custom APT config
echo "  Configuring APT..."
cat > /etc/apt/sources.list <<SOURCES
# Archy Main Repository
deb http://deb.debian.org/debian unstable main contrib non-free
SOURCES

# Custom OS identity
echo "  Setting OS identity..."
cat > /etc/os-release <<OS_RELEASE
NAME="$DISTRO_NAME"
PRETTY_NAME="$DISTRO_NAME $DISTRO_VERSION"
VERSION="$DISTRO_VERSION ($BUILD_DATE)"
ID=archy
ID_LIKE=debian
HOME_URL="https://archy.org"
SUPPORT_URL="https://archy.org/support"
BUG_REPORT_URL="https://archy.org/bugs"
OS_RELEASE

# Custom login messages
cat > /etc/issue <<ISSUE
$DISTRO_NAME $DISTRO_VERSION \\n \\l

ISSUE
cp /etc/issue /etc/issue.net

cat > /etc/motd <<MOTD
Welcome to $DISTRO_NAME - The Minimalist's Dream
Type 'archy-help' for basic commands

MOTD

# === Custom Commands ===
echo "  Creating custom commands..."

# Help system
cat > /usr/bin/archy-help <<'HELP'
#!/bin/bash
echo -e "\033[1;36m$DISTRO_NAME Help System\033[0m"
echo "archy-install   - Install $DISTRO_NAME to disk"
echo "archy-upgrade   - Update the system"
echo "archy-init      - First-time setup"
echo "archy-help      - Show this help"
echo "au              - Alias for archy-upgrade"
echo "ai <pkg>        - Install package"
echo "ar <pkg>        - Remove package"
echo "as <term>       - Search packages"
HELP
chmod +x /usr/bin/archy-help

# Installer
cat > /usr/bin/archy-install <<'INSTALL'
#!/bin/bash
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# Header
echo -e "\033[1;36m"
cat <<'HEADER'
     _          _       
    /_\  _ _ __| |_ ___ 
   / _ \| '_/ _|  _/ -_)
  /_/ \_\_| \__|\__\___| 

    ____            _         
   |  _ \ __ _ _ __| |__  ___ 
   | |_) / _` | '__| '_ \/ __|
   |  _ < (_| | |  | |_) \__ \
   |_| \_\__,_|_|  |_.__/|___/

      [ Minimalist Debian ]
HEADER
echo -e "\033[0m"

# Check root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Error: This script must be run as root${NC}" 
   exit 1
fi

# Disk selection
echo -e "${BLUE}Available disks:${NC}"
lsblk -d -o NAME,SIZE,MODEL
echo ""
read -p "Enter target disk (e.g. sda): " DISK
DISK="/dev/$DISK"

# Partitioning
echo -e "${BLUE}Partitioning options:${NC}"
echo "1) Auto-partition (GPT, 512MB EFI, rest as root)"
echo "2) Manual (cfdisk)"
read -p "Select option [1/2]: " PART_OPTION

case $PART_OPTION in
    1)
        echo -e "${GREEN}Auto-partitioning $DISK...${NC}"
        parted -s "$DISK" mklabel gpt
        parted -s "$DISK" mkpart primary 1MiB 513MiB
        parted -s "$DISK" set 1 esp on
        parted -s "$DISK" mkpart primary 513MiB 100%
        mkfs.fat -F32 "${DISK}1"
        mkfs.ext4 "${DISK}2"
        mount "${DISK}2" /mnt
        mkdir -p /mnt/boot/efi
        mount "${DISK}1" /mnt/boot/efi
        ;;
    2)
        cfdisk "$DISK"
        echo -e "${YELLOW}Please mount partitions manually and re-run${NC}"
        exit
        ;;
    *)
        echo -e "${RED}Invalid option${NC}"
        exit 1
        ;;
esac

# Installation
echo -e "${BLUE}Installing base system...${NC}"
debootstrap unstable /mnt http://deb.debian.org/debian

# Chroot setup
arch-chroot /mnt /bin/bash <<CHROOT
# System config
echo "$DISTRO_NAME" > /etc/hostname
ln -sf /usr/share/zoneinfo/UTC /etc/localtime

# Base packages
apt update
apt install -y --no-install-recommends \
    linux-image-$ARCH grub-efi-$ARCH sudo bash nano less \
    network-manager systemd udev apt-listbugs locales

# Bootloader
grub-install --target=${ARCH}-efi --efi-directory=/boot/efi --bootloader-id=$DISTRO_NAME
update-grub

# User setup
useradd -m -G sudo -s /bin/bash user
echo "user:archy" | chpasswd
echo "root:archy" | chpasswd

# Services
systemctl enable NetworkManager

# Locale
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
update-locale LANG=en_US.UTF-8

# Copy our custom configs
cp /usr/bin/archy-* /usr/bin/
cp /etc/{os-release,issue,issue.net,motd} /etc/
CHROOT

echo -e "${GREEN}Installation complete!${NC}"
echo -e "Unmount and reboot with:"
echo -e "umount -R /mnt"
echo -e "reboot"
INSTALL
chmod +x /usr/bin/archy-install

# Init system
cat > /usr/bin/archy-init <<'INIT'
#!/bin/bash
set -e
echo -e "\033[1;36m$DISTRO_NAME Initialization\033[0m"
echo "[*] Setting up system..."

timedatectl set-ntp true
apt update
apt full-upgrade -y

echo "[*] Configuring locales..."
dpkg-reconfigure locales

echo "[*] Setting hostname..."
read -p "Enter hostname: " HOSTNAME
echo "$HOSTNAME" > /etc/hostname

echo -e "\033[1;32mInitialization complete!\033[0m"
echo "Run 'archy-upgrade' to update your system"
INIT
chmod +x /usr/bin/archy-init

# Upgrade system
cat > /usr/bin/archy-upgrade <<'UPGRADE'
#!/bin/bash
set -e
echo -e "\033[1;34m$DISTRO_NAME Upgrade System\033[0m"
echo "[*] Updating package lists..."
apt update
echo "[*] Checking for upgrades..."
apt list --upgradable

read -p "Do you want to proceed with upgrade? [y/N] " choice
case "$choice" in 
  y|Y )
    echo "[*] Upgrading system..."
    apt full-upgrade -y
    echo "[*] Cleaning up..."
    apt autoremove -y
    echo -e "\033[1;32mUpgrade complete!\033[0m"
    ;;
  * )
    echo "Upgrade cancelled."
    ;;
esac
UPGRADE
chmod +x /usr/bin/archy-upgrade

# === User Environment ===
echo "  Configuring user environment..."

# Aliases
cat >> /etc/skel/.bashrc <<BASHRC
# Archy Aliases
alias au='sudo archy-upgrade'
alias ai='sudo apt install'
alias ar='sudo apt remove'
alias as='apt search'
alias ap='apt show'
alias auh='apt update && apt list --upgradable'
BASHRC

# GRUB Theme
echo "  Configuring GRUB theme..."
mkdir -p /boot/grub/themes/archy
cat > /boot/grub/themes/archy/theme.txt <<THEME
# GRUB Theme for $DISTRO_NAME
title-text: "$DISTRO_NAME"
title-font: "DejaVu Sans Bold 16"
title-color: "#00ffff"

+ boot_menu {
    left = 15%
    top = 30%
    width = 70%
    height = 40%
    item_font = "DejaVu Sans 12"
    item_color = "#ffffff"
    selected_item_color = "#00ffff"
    item_padding = 1
    item_spacing = 1
    item_height = 20
}

+ label {
    top = 80%
    left = 15%
    width = 70%
    align = "center"
    color = "#aaaaaa"
    text = "Version $DISTRO_VERSION - $BUILD_DATE"
    font = "DejaVu Sans 10"
}
THEME

echo 'GRUB_THEME="/boot/grub/themes/archy/theme.txt"' >> /etc/default/grub
update-grub
EOF

# === ISO Creation ===
echo "[4/6] 📀 Creating ISO structure..."
sudo chroot "$WORKDIR" /bin/bash <<'EOF'
set -e

# Create ISO structure
mkdir -p /iso/{boot/isolinux,live}

# Copy kernel and initrd
cp /boot/vmlinuz-* /iso/live/vmlinuz
cp /boot/initrd.img-* /iso/live/initrd.img

# ISOLINUX config
cat > /iso/boot/isolinux/isolinux.cfg <<EOL
UI menu.c32
PROMPT 0
TIMEOUT 300

DEFAULT archy
LABEL archy
  MENU LABEL Install $DISTRO_NAME
  LINUX /live/vmlinuz
  INITRD /live/initrd.img
  APPEND boot=live components quiet splash

LABEL rescue
  MENU LABEL Rescue Mode
  LINUX /live/vmlinuz
  INITRD /live/initrd.img
  APPEND boot=live components rescue
EOL

# Copy ISOLINUX files
cp /usr/lib/ISOLINUX/isolinux.bin /iso/boot/isolinux/
cp /usr/lib/syslinux/modules/bios/* /iso/boot/isolinux/

# Create EFI boot image
mkdir -p /iso/boot/grub
grub-mkstandalone -O x86_64-efi -o /iso/boot/grub/efi.img "boot/grub/grub.cfg=./grub.cfg"

# Create ISO
xorriso -as mkisofs \
  -o /Archy.iso \
  -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
  -c boot/isolinux/boot.cat \
  -b boot/isolinux/isolinux.bin \
  -no-emul-boot -boot-load-size 4 -boot-info-table \
  -eltorito-alt-boot \
  -e boot/grub/efi.img \
  -no-emul-boot \
  -isohybrid-gpt-basdat \
  -volid "$DISTRO_NAME" \
  /iso
EOF

# === Finalize ===
echo "[5/6] 🔄 Moving ISO..."
sudo mv "$WORKDIR/Archy.iso" "$ISOFILE"

echo "[6/6] 🧹 Cleaning up..."
sudo rm -rf "$WORKDIR"

# === Completion ===
echo -e "\n\033[1;32m✅ $DISTRO_NAME ISO successfully created: $ISOFILE\033[0m"
echo -e "💡 Test with: \033[1;36mqemu-system-x86_64 -cdrom $ISOFILE -m 2G\033[0m\n"