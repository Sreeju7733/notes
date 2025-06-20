#!/bin/bash
set -euo pipefail

# ---- CONFIG ----
export DISTRO_NAME="Archy"
export DISTRO_VERSION="1.0"
export ARCH="${ARCH:-amd64}"
export WORKDIR="$PWD/archy-build-$ARCH"
export ISOFILE="$PWD/${DISTRO_NAME}-${DISTRO_VERSION}-$ARCH.iso"
export DEBIAN_URL="http://deb.debian.org/debian"
export BUILD_DATE=$(date +%Y-%m-%d)

# ---- DEPENDENCY CHECK ----
echo "[*] Checking dependencies..."
function ensure_pkg() {
    local pkg="$1" bin="$2"
    if ! command -v "$bin" &>/dev/null; then
        echo "Installing dependency: $pkg"
        apt-get update
        apt-get install -y "$pkg"
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
rm -rf "$WORKDIR" || true

# ---- BOOTSTRAP BASE SYSTEM ----
echo "[2/6] Bootstrapping base system..."
debootstrap \
    --arch="$ARCH" \
    --variant=minbase \
    --exclude=debian-faq,debian-reference,debian-installer \
    --include=apt,dpkg,linux-image-$ARCH,systemd \
    unstable "$WORKDIR" "$DEBIAN_URL"

# ---- MOUNT SYSTEM DIRECTORIES ----
mkdir -p "$WORKDIR"/{dev,proc,sys}
mount --bind /dev "$WORKDIR/dev"
mount --bind /dev/pts "$WORKDIR/dev/pts"
mount -t proc proc "$WORKDIR/proc"
mount -t sysfs sys "$WORKDIR/sys"

# ---- CUSTOMIZE CHROOT ----
echo "[3/6] Customizing system in chroot..."
chroot "$WORKDIR" /bin/bash <<'CHROOT'
set -e

export DEBIAN_FRONTEND=noninteractive

# Install required packages
apt-get update
apt-get install -y --no-install-recommends \
    bash coreutils systemd udev sudo nano less grub2 \
    network-manager wget curl fdisk parted locales \
    apt-listbugs xorriso isolinux syslinux-common dosfstools grub-efi-amd64-bin

# Remove unwanted branding and docs
{ apt-get purge -y debian-* os-prober tasksel reportbug || true; } >/dev/null 2>&1
rm -rf /usr/share/{doc,man,doc-base,common-licenses,debian*} || true
rm -rf /etc/{network,default,init.d,rc*.d,dpkg} || true
rm -f /etc/{issue,issue.net,os-release,motd,legal} || true

# APT sources
cat > /etc/apt/sources.list <<EOF
deb http://deb.debian.org/debian unstable main contrib non-free
EOF

# OS identity
cat > /etc/os-release <<EOF
NAME="Archy"
PRETTY_NAME="Archy 1.0"
VERSION="1.0 ($BUILD_DATE)"
ID=archy
ID_LIKE=debian
HOME_URL="https://archy.org"
SUPPORT_URL="https://archy.org/support"
BUG_REPORT_URL="https://archy.org/bugs"
EOF

# Login messages
cat > /etc/issue <<EOF
Archy 1.0 \\n \\l
EOF
cp /etc/issue /etc/issue.net

cat > /etc/motd <<EOF
Welcome to Archy - The Minimalist's Dream
Type 'archy-help' for basic commands
EOF

# Custom commands
cat > /usr/bin/archy-help <<'EOF'
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
EOF
chmod +x /usr/bin/archy-help

# Installer script
cat > /usr/bin/archy-install <<'EOF'
#!/bin/bash
set -e
echo -e "\033[1;36mArchy Installer\033[0m"
if [[ $EUID -ne 0 ]]; then echo "Run as root"; exit 1; fi
lsblk -d -o NAME,SIZE,MODEL
read -p "Enter target disk (e.g. sda): " DISK
DISK="/dev/$DISK"
echo "1) Auto (GPT, 512MB EFI, rest as root)"
echo "2) Manual (cfdisk)"
read -p "Option [1/2]: " OPT
case $OPT in
    1)
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
    2) cfdisk "$DISK"; echo "Mount partitions manually and re-run"; exit;;
    *) echo "Invalid option"; exit 1;;
esac
debootstrap unstable /mnt http://deb.debian.org/debian
arch-chroot /mnt /bin/bash <<'CHROOT2'
apt-get update
apt-get install -y linux-image-amd64 grub-efi-amd64 sudo bash nano less network-manager systemd udev locales
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Archy
update-grub
useradd -m -G sudo -s /bin/bash user
echo "user:archy" | chpasswd
echo "root:archy" | chpasswd
systemctl enable NetworkManager
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
update-locale LANG=en_US.UTF-8
CHROOT2
echo "Done. Unmount and reboot."
EOF
chmod +x /usr/bin/archy-install

# archy-init
cat > /usr/bin/archy-init <<'EOF'
#!/bin/bash
set -e
echo -e "\033[1;36mArchy Initialization\033[0m"
timedatectl set-ntp true
apt-get update
apt-get full-upgrade -y
dpkg-reconfigure locales
read -p "Enter hostname: " HOSTNAME
echo "$HOSTNAME" > /etc/hostname
echo -e "\033[1;32mInitialization complete!\033[0m"
EOF
chmod +x /usr/bin/archy-init

# archy-upgrade
cat > /usr/bin/archy-upgrade <<'EOF'
#!/bin/bash
set -e
echo -e "\033[1;34mArchy Upgrade System\033[0m"
apt-get update
apt-get full-upgrade -y
apt-get autoremove -y
echo -e "\033[1;32mUpgrade complete!\033[0m"
EOF
chmod +x /usr/bin/archy-upgrade

# Aliases for users
cat >> /etc/skel/.bashrc <<EOF
alias au='sudo archy-upgrade'
alias ai='sudo apt install'
alias ar='sudo apt remove'
alias as='apt search'
alias ap='apt show'
alias auh='apt update && apt list --upgradable'
EOF

# GRUB theme
mkdir -p /boot/grub/themes/archy
cat > /boot/grub/themes/archy/theme.txt <<EOF
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
EOF

[ -f /etc/default/grub ] || touch /etc/default/grub
echo 'GRUB_THEME="/boot/grub/themes/archy/theme.txt"' >> /etc/default/grub
update-grub
CHROOT

# ---- UNMOUNT SYSTEM DIRECTORIES ----
echo "[4/6] Unmounting system directories..."
for d in proc sys dev/pts dev; do
    umount -l "$WORKDIR/$d" 2>/dev/null || true
done

# ---- ISO CREATION ----
echo "[5/6] Creating ISO structure..."
mkdir -p "$WORKDIR/iso"/{boot/isolinux,live}
cp "$WORKDIR"/boot/vmlinuz-* "$WORKDIR/iso/live/vmlinuz"
cp "$WORKDIR"/boot/initrd.img-* "$WORKDIR/iso/live/initrd.img"

cat > "$WORKDIR/iso/boot/isolinux/isolinux.cfg" <<EOF
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
EOF

cp /usr/lib/ISOLINUX/isolinux.bin "$WORKDIR/iso/boot/isolinux/"
cp /usr/lib/syslinux/modules/bios/* "$WORKDIR/iso/boot/isolinux/"

mkdir -p "$WORKDIR/iso/boot/grub"
chroot "$WORKDIR" grub-mkstandalone -O x86_64-efi -o /iso/boot/grub/efi.img "boot/grub/grub.cfg=./grub.cfg"

xorriso -as mkisofs \
  -o "$ISOFILE" \
  -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
  -c boot/isolinux/boot.cat \
  -b boot/isolinux/isolinux.bin \
  -no-emul-boot -boot-load-size 4 -boot-info-table \
  -eltorito-alt-boot \
  -e boot/grub/efi.img \
  -no-emul-boot \
  -isohybrid-gpt-basdat \
  -volid "Archy" \
  "$WORKDIR/iso"

echo "[6/6] Cleaning up build..."
rm -rf "$WORKDIR"
echo -e "\n\033[1;32m✅ Archy ISO created: $ISOFILE\033[0m"
echo -e "💡 Test with: \033[1;36mqemu-system-x86_64 -cdrom $ISOFILE -m 2G\033[0m\n"
