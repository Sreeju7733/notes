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

# === Dependency Install (host) ===
function check_install() {
    local pkg="$1" bin="$2"
    if ! command -v "$bin" &>/dev/null; then
        echo "Installing dependency: $pkg"
        apt update
        apt install -y "$pkg"
    fi
}
check_install debootstrap debootstrap
check_install xorriso xorriso
check_install parted parted
check_install dosfstools mkfs.fat
check_install grub2 grub-mkrescue
check_install isolinux isolinux
check_install syslinux-common isohdpfx.bin
check_install grub-efi-amd64-bin grub-mkstandalone

# === Clean old build ===
echo "[1/6] 🧹 Cleaning old build..."
rm -rf "$WORKDIR"

# === Create minimal base ===
echo "[2/6] 🏗️  Creating minimal base system..."
debootstrap \
    --arch="$ARCH" \
    --variant=minbase \
    --exclude=debian-archive-keyring,debian-faq,debian-reference,debian-installer \
    --include=apt,dpkg,linux-image-$ARCH,systemd \
    unstable "$WORKDIR" "$DEBIAN_URL"

# === Mount system dirs for chroot ===
mount --bind /dev "$WORKDIR/dev"
mount --bind /dev/pts "$WORKDIR/dev/pts"
mount --bind /proc "$WORKDIR/proc"
mount --bind /sys "$WORKDIR/sys"

# === Chroot system customization ===
echo "[3/6] 🎨 Customizing Archy system..."
chroot "$WORKDIR" /bin/bash <<'EOF'
set -e

export DEBIAN_FRONTEND=noninteractive

apt update
apt install -y --no-install-recommends \
    bash coreutils systemd udev sudo nano less grub2 \
    network-manager wget curl fdisk parted locales \
    apt-listbugs xorriso isolinux syslinux-common dosfstools grub-efi-amd64-bin

# Remove Debian branding and docs
apt purge -y debian-* os-prober tasksel reportbug || true
rm -rf /usr/share/{doc,man,doc-base,common-licenses,debian*}
rm -rf /etc/{network,default,init.d,rc*.d,dpkg,apt/apt.conf.d}
rm -f /etc/{issue,issue.net,os-release,motd,legal}

# Custom APT config
cat > /etc/apt/sources.list <<SOURCES
deb http://deb.debian.org/debian unstable main contrib non-free
SOURCES

# Custom OS identity
cat > /etc/os-release <<OS_RELEASE
NAME="Archy"
PRETTY_NAME="Archy 1.0"
VERSION="1.0 ($BUILD_DATE)"
ID=archy
ID_LIKE=debian
HOME_URL="https://archy.org"
SUPPORT_URL="https://archy.org/support"
BUG_REPORT_URL="https://archy.org/bugs"
OS_RELEASE

# Custom login messages
cat > /etc/issue <<ISSUE
Archy 1.0 \\n \\l
ISSUE
cp /etc/issue /etc/issue.net

cat > /etc/motd <<MOTD
Welcome to Archy - The Minimalist's Dream
Type 'archy-help' for basic commands

MOTD

# === Custom Commands ===
cat > /usr/bin/archy-help <<'HELP'
#!/bin/bash
echo -e "\033[1;36mArchy Help System\033[0m"
echo "archy-install   - Install Archy to disk"
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
RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
echo -e "\033[1;36m"
cat <<'HEADER'
     _          _       
    /_\  _ _ __| |_ ___ 
   / _ \| '_/ _|  _/ -_)
  /_/ \_\_| \__|\__\___| 
      [ Minimalist Debian ]
HEADER
echo -e "\033[0m"
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Error: This script must be run as root${NC}" 
   exit 1
fi
echo -e "${BLUE}Available disks:${NC}"
lsblk -d -o NAME,SIZE,MODEL
echo ""
read -p "Enter target disk (e.g. sda): " DISK
DISK="/dev/$DISK"
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
echo -e "${BLUE}Installing base system...${NC}"
debootstrap unstable /mnt http://deb.debian.org/debian
arch-chroot /mnt /bin/bash <<CHROOT
echo "Archy" > /etc/hostname
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
apt update
apt install -y --no-install-recommends \
    linux-image-$ARCH grub-efi-$ARCH sudo bash nano less \
    network-manager systemd udev apt-listbugs locales
grub-install --target=${ARCH}-efi --efi-directory=/boot/efi --bootloader-id=Archy
update-grub
useradd -m -G sudo -s /bin/bash user
echo "user:archy" | chpasswd
echo "root:archy" | chpasswd
systemctl enable NetworkManager
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
update-locale LANG=en_US.UTF-8
cp /usr/bin/archy-* /usr/bin/
cp /etc/{os-release,issue,issue.net,motd} /etc/
CHROOT
echo -e "${GREEN}Installation complete!${NC}"
echo -e "Unmount and reboot with:"
echo -e "umount -R /mnt"
echo -e "reboot"
INSTALL
chmod +x /usr/bin/archy-install

cat > /usr/bin/archy-init <<'INIT'
#!/bin/bash
set -e
echo -e "\033[1;36mArchy Initialization\033[0m"
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

cat > /usr/bin/archy-upgrade <<'UPGRADE'
#!/bin/bash
set -e
echo -e "\033[1;34mArchy Upgrade System\033[0m"
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

cat >> /etc/skel/.bashrc <<BASHRC
# Archy Aliases
alias au='sudo archy-upgrade'
alias ai='sudo apt install'
alias ar='sudo apt remove'
alias as='apt search'
alias ap='apt show'
alias auh='apt update && apt list --upgradable'
BASHRC

mkdir -p /boot/grub/themes/archy
cat > /boot/grub/themes/archy/theme.txt <<THEME
# GRUB Theme for Archy
title-text: "Archy"
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
    text = "Version 1.0 - $BUILD_DATE"
    font = "DejaVu Sans 10"
}
THEME

echo 'GRUB_THEME="/boot/grub/themes/archy/theme.txt"' >> /etc/default/grub
update-grub
EOF

# === Unmount system dirs ===
umount "$WORKDIR/dev/pts"
umount "$WORKDIR/dev"
umount "$WORKDIR/proc"
umount "$WORKDIR/sys"

# === ISO Creation ===
echo "[4/6] 📀 Creating ISO structure..."
chroot "$WORKDIR" /bin/bash <<'EOF'
set -e
mkdir -p /iso/{boot/isolinux,live}
cp /boot/vmlinuz-* /iso/live/vmlinuz
cp /boot/initrd.img-* /iso/live/initrd.img
cat > /iso/boot/isolinux/isolinux.cfg <<EOL
UI menu.c32
PROMPT 0
TIMEOUT 300
DEFAULT archy
LABEL archy
  MENU LABEL Install Archy
  LINUX /live/vmlinuz
  INITRD /live/initrd.img
  APPEND boot=live components quiet splash
LABEL rescue
  MENU LABEL Rescue Mode
  LINUX /live/vmlinuz
  INITRD /live/initrd.img
  APPEND boot=live components rescue
EOL
cp /usr/lib/ISOLINUX/isolinux.bin /iso/boot/isolinux/
cp /usr/lib/syslinux/modules/bios/* /iso/boot/isolinux/
mkdir -p /iso/boot/grub
grub-mkstandalone -O x86_64-efi -o /iso/boot/grub/efi.img "boot/grub/grub.cfg=./grub.cfg"
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
  -volid "Archy" \
  /iso
EOF

echo "[5/6] 🔄 Moving ISO..."
mv "$WORKDIR/Archy.iso" "$ISOFILE"

echo "[6/6] 🧹 Cleaning up..."
rm -rf "$WORKDIR"

echo -e "\n\033[1;32m✅ Archy ISO successfully created: $ISOFILE\033[0m"
echo -e "💡 Test with: \033[1;36mqemu-system-x86_64 -cdrom $ISOFILE -m 2G\033[0m\n"
