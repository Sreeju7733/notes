#!/bin/bash
set -euo pipefail

# ---- CONFIG ----
export DISTRO_NAME="Archy"
export DISTRO_VERSION="1.0"
export ARCH="amd64"
export WORKDIR="$PWD/archy-build-$ARCH"
export ISOFILE="$PWD/${DISTRO_NAME}-${DISTRO_VERSION}-$ARCH.iso"
export DEBIAN_URL="http://deb.debian.org/debian"
export BUILD_DATE=$(date +%Y-%m-%d)

# Robust cleanup function
cleanup() {
    echo "[!] Cleaning up mounts..."
    # Unmount in reverse order
    for dir in proc sys dev/pts dev run; do
        if mountpoint -q "${WORKDIR}/${dir}"; then
            umount -lf "${WORKDIR}/${dir}" 2>/dev/null || echo "[-] Warning: Failed to unmount ${dir}"
        fi
    done
    echo "[!] Removing work directory..."
    if [ -d "$WORKDIR" ]; then
        rm -rf "$WORKDIR" || echo "[-] Warning: Failed to remove $WORKDIR"
    fi
}

# Register cleanup trap
trap cleanup EXIT INT TERM

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
ensure_pkg squashfs-tools mksquashfs
ensure_pkg live-boot live-boot
ensure_pkg zstd zstd

echo "[*] Dependencies OK"

# ---- CLEAN PREVIOUS BUILD ----
echo "[1/6] Cleaning old build directory..."
cleanup

# ---- BOOTSTRAP BASE SYSTEM ----
echo "[2/6] Bootstrapping base system..."
debootstrap \
    --arch="$ARCH" \
    --variant=minbase \
    --exclude=debian-faq,debian-reference,debian-installer \
    --include=apt,dpkg,linux-image-$ARCH,systemd \
    unstable "$WORKDIR" "$DEBIAN_URL"

# ---- MOUNT SYSTEM DIRECTORIES ----
echo "[*] Mounting system directories..."
mkdir -p "$WORKDIR"/{dev,proc,sys,run}
mount --bind /dev "$WORKDIR/dev"
mount --bind /dev/pts "$WORKDIR/dev/pts"
mount -t proc proc "$WORKDIR/proc"
mount -t sysfs sys "$WORKDIR/sys"
mount -t tmpfs tmpfs "$WORKDIR/run"

# ---- CUSTOMIZE CHROOT ----
echo "[3/6] Customizing system in chroot..."
chroot "$WORKDIR" /bin/bash <<'CHROOT'
set -e

export DEBIAN_FRONTEND=noninteractive
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

# Install required packages
apt-get update
apt-get install -y --no-install-recommends \
    bash coreutils systemd udev sudo nano less grub2 \
    network-manager wget curl fdisk parted locales \
    apt-listbugs xorriso isolinux syslinux-common dosfstools \
    grub-efi-amd64-bin live-boot zstd squashfs-tools

# Remove unwanted branding and docs
{ apt-get purge -y debian-* os-prober tasksel reportbug || true; } >/dev/null
rm -rf /usr/share/{doc,man,doc-base,common-licenses,debian*} 2>/dev/null || true
rm -rf /etc/{network,default,init.d,rc*.d,dpkg} 2>/dev/null || true
rm -f /etc/{issue,issue.net,os-release,motd,legal} 2>/dev/null || true

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
cp /etc/issue /etc/issue.net 2>/dev/null || true

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
lsblk -d -o NAME,SIZE,MODEL 2>/dev/null || true
read -p "Enter target disk (e.g. sda): " DISK
DISK="/dev/$DISK"
echo "1) Auto (GPT, 512MB EFI, rest as root)"
echo "2) Manual (cfdisk)"
read -p "Option [1/2]: " OPT
case $OPT in
    1)
        parted -s "$DISK" mklabel gpt 2>/dev/null || true
        parted -s "$DISK" mkpart primary 1MiB 513MiB 2>/dev/null || true
        parted -s "$DISK" set 1 esp on 2>/dev/null || true
        parted -s "$DISK" mkpart primary 513MiB 100% 2>/dev/null || true
        mkfs.fat -F32 "${DISK}1" 2>/dev/null || true
        mkfs.ext4 "${DISK}2" 2>/dev/null || true
        mount "${DISK}2" /mnt 2>/dev/null || true
        mkdir -p /mnt/boot/efi 2>/dev/null || true
        mount "${DISK}1" /mnt/boot/efi 2>/dev/null || true
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
debootstrap unstable /mnt "$DEBIAN_URL" || true
arch-chroot /mnt /bin/bash <<'CHROOT2'
apt-get update || true
apt-get install -y linux-image-amd64 grub-efi-amd64 sudo bash nano less network-manager systemd udev locales || true
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Archy || true
update-grub || true
useradd -m -G sudo -s /bin/bash user || true
echo "user:archy" | chpasswd || true
echo "root:archy" | chpasswd || true
systemctl enable NetworkManager || true
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen || true
locale-gen || true
update-locale LANG=en_US.UTF-8 || true
CHROOT2
echo "Done. Unmount and reboot."
EOF
chmod +x /usr/bin/archy-install

# archy-init
cat > /usr/bin/archy-init <<'EOF'
#!/bin/bash
set -e
echo -e "\033[1;36mArchy Initialization\033[0m"
timedatectl set-ntp true || true
apt-get update || true
apt-get full-upgrade -y || true
dpkg-reconfigure locales || true
read -p "Enter hostname: " HOSTNAME
echo "$HOSTNAME" > /etc/hostname || true
echo -e "\033[1;32mInitialization complete!\033[0m"
EOF
chmod +x /usr/bin/archy-init

# archy-upgrade
cat > /usr/bin/archy-upgrade <<'EOF'
#!/bin/bash
set -e
echo -e "\033[1;34mArchy Upgrade System\033[0m"
apt-get update || true
apt-get full-upgrade -y || true
apt-get autoremove -y || true
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
update-grub || true

# Fix initramfs configuration
echo "COMPRESS=zstd" > /etc/initramfs-tools/conf.d/compression.conf
echo "MODULES=most" > /etc/initramfs-tools/conf.d/modules.conf
echo "DEVICE_MAPPER=no" > /etc/initramfs-tools/conf.d/dm.conf
update-initramfs -u -k all || true

# Live environment setup
mkdir -p /lib/live/config
cat > /lib/live/config/0030-archy <<'EOF'
#!/bin/sh
set -e
echo "archy-live" > /etc/hostname
cat > /etc/motd <<'MOTD'
Welcome to Archy Linux - The Minimalist's Dream
Type 'archy-help' for basic commands
MOTD
EOF
chmod +x /lib/live/config/0030-archy

# Create user
useradd -m -s /bin/bash user
echo "user:archy" | chpasswd
echo "root:archy" | chpasswd
CHROOT

# ---- UNMOUNT SYSTEM DIRECTORIES ----
echo "[4/6] Unmounting system directories..."
cleanup

# ---- ISO CREATION ----
echo "[5/6] Creating ISO structure..."
mkdir -p "$WORKDIR/iso"/{live,boot/grub,EFI/BOOT,boot/isolinux}

# Copy kernel files
VMLINUZ=$(find "$WORKDIR/boot" -name vmlinuz-* -print -quit)
INITRD=$(find "$WORKDIR/boot" -name initrd.img-* -print -quit)
[ -n "$VMLINUZ" ] && cp "$VMLINUZ" "$WORKDIR/iso/live/vmlinuz"
[ -n "$INITRD" ] && cp "$INITRD" "$WORKDIR/iso/live/initrd.img"

# Create GRUB configuration
cat > "$WORKDIR/iso/boot/grub/grub.cfg" <<'EOF'
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
grub-mkstandalone -O x86_64-efi -o "$WORKDIR/iso/EFI/BOOT/BOOTX64.EFI" "boot/grub/grub.cfg=$WORKDIR/iso/boot/grub/grub.cfg"

# Prepare BIOS boot files
mkdir -p "$WORKDIR/iso/boot/grub/i386-pc"
cp /usr/lib/grub/i386-pc/boot_hybrid.img "$WORKDIR/iso/boot/grub/i386-pc/"
cp /usr/lib/grub/i386-pc/eltorito.img "$WORKDIR/iso/boot/grub/i386-pc/"

# Create isolinux structure
cp /usr/lib/ISOLINUX/isolinux.bin "$WORKDIR/iso/boot/isolinux/"
cp /usr/lib/syslinux/modules/bios/* "$WORKDIR/iso/boot/isolinux/"

cat > "$WORKDIR/iso/boot/isolinux/isolinux.cfg" <<'EOF'
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

# ---- GENERATE ISO ----
echo "[6/6] Creating bootable ISO..."
xorriso -as mkisofs \
  -r -V "ARCHY_LIVE" \
  -o "$ISOFILE" \
  -J -joliet-long \
  -iso-level 3 \
  -partition_offset 16 \
  --grub2-mbr /usr/lib/grub/i386-pc/boot_hybrid.img \
  --mbr-force-bootable \
  -append_partition 2 0xEF "$WORKDIR/iso/EFI/BOOT/BOOTX64.EFI" \
  -appended_part_as_gpt \
  -c boot/isolinux/boot.cat \
  -b boot/isolinux/isolinux.bin \
  -no-emul-boot -boot-load-size 4 -boot-info-table \
  -eltorito-alt-boot \
  -e '--interval:appended_partition_2:all::' \
  -no-emul-boot \
  -isohybrid-gpt-basdat \
  "$WORKDIR/iso"

# ---- FINAL VERIFICATION ----
if [ -f "$ISOFILE" ]; then
    ISO_SIZE=$(du -h "$ISOFILE" | cut -f1)
    echo -e "\n\033[1;32m🎉 Successfully created Archy Linux ISO!\033[0m"
    echo -e "   File: \033[1;34m$ISOFILE\033[0m"
    echo -e "   Size: \033[1;34m$ISO_SIZE\033[0m"
    echo -e "\n💡 Test with: \033[1;36mqemu-system-x86_64 -cdrom \"$ISOFILE\" -m 2G\033[0m"
else
    echo -e "\n\033[1;31m❌ ISO creation failed. Check output for errors.\033[0m"
    exit 1
fi#!/bin/bash
set -euo pipefail

# ---- CONFIG ----
export DISTRO_NAME="Archy"
export DISTRO_VERSION="1.0"
export ARCH="amd64"
export WORKDIR="$PWD/archy-build-$ARCH"
export ISOFILE="$PWD/${DISTRO_NAME}-${DISTRO_VERSION}-$ARCH.iso"
export DEBIAN_URL="http://deb.debian.org/debian"
export BUILD_DATE=$(date +%Y-%m-%d)

# Robust cleanup function
cleanup() {
    echo "[!] Cleaning up mounts..."
    # Unmount in reverse order
    for dir in proc sys dev/pts dev run; do
        if mountpoint -q "${WORKDIR}/${dir}"; then
            umount -lf "${WORKDIR}/${dir}" 2>/dev/null || echo "[-] Warning: Failed to unmount ${dir}"
        fi
    done
    echo "[!] Removing work directory..."
    if [ -d "$WORKDIR" ]; then
        rm -rf "$WORKDIR" || echo "[-] Warning: Failed to remove $WORKDIR"
    fi
}

# Register cleanup trap
trap cleanup EXIT INT TERM

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
ensure_pkg squashfs-tools mksquashfs
ensure_pkg live-boot live-boot
ensure_pkg zstd zstd

echo "[*] Dependencies OK"

# ---- CLEAN PREVIOUS BUILD ----
echo "[1/6] Cleaning old build directory..."
cleanup

# ---- BOOTSTRAP BASE SYSTEM ----
echo "[2/6] Bootstrapping base system..."
debootstrap \
    --arch="$ARCH" \
    --variant=minbase \
    --exclude=debian-faq,debian-reference,debian-installer \
    --include=apt,dpkg,linux-image-$ARCH,systemd \
    unstable "$WORKDIR" "$DEBIAN_URL"

# ---- MOUNT SYSTEM DIRECTORIES ----
echo "[*] Mounting system directories..."
mkdir -p "$WORKDIR"/{dev,proc,sys,run}
mount --bind /dev "$WORKDIR/dev"
mount --bind /dev/pts "$WORKDIR/dev/pts"
mount -t proc proc "$WORKDIR/proc"
mount -t sysfs sys "$WORKDIR/sys"
mount -t tmpfs tmpfs "$WORKDIR/run"

# ---- CUSTOMIZE CHROOT ----
echo "[3/6] Customizing system in chroot..."
chroot "$WORKDIR" /bin/bash <<'CHROOT'
set -e

export DEBIAN_FRONTEND=noninteractive
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

# Install required packages
apt-get update
apt-get install -y --no-install-recommends \
    bash coreutils systemd udev sudo nano less grub2 \
    network-manager wget curl fdisk parted locales \
    apt-listbugs xorriso isolinux syslinux-common dosfstools \
    grub-efi-amd64-bin live-boot zstd squashfs-tools

# Remove unwanted branding and docs
{ apt-get purge -y debian-* os-prober tasksel reportbug || true; } >/dev/null
rm -rf /usr/share/{doc,man,doc-base,common-licenses,debian*} 2>/dev/null || true
rm -rf /etc/{network,default,init.d,rc*.d,dpkg} 2>/dev/null || true
rm -f /etc/{issue,issue.net,os-release,motd,legal} 2>/dev/null || true

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
cp /etc/issue /etc/issue.net 2>/dev/null || true

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
lsblk -d -o NAME,SIZE,MODEL 2>/dev/null || true
read -p "Enter target disk (e.g. sda): " DISK
DISK="/dev/$DISK"
echo "1) Auto (GPT, 512MB EFI, rest as root)"
echo "2) Manual (cfdisk)"
read -p "Option [1/2]: " OPT
case $OPT in
    1)
        parted -s "$DISK" mklabel gpt 2>/dev/null || true
        parted -s "$DISK" mkpart primary 1MiB 513MiB 2>/dev/null || true
        parted -s "$DISK" set 1 esp on 2>/dev/null || true
        parted -s "$DISK" mkpart primary 513MiB 100% 2>/dev/null || true
        mkfs.fat -F32 "${DISK}1" 2>/dev/null || true
        mkfs.ext4 "${DISK}2" 2>/dev/null || true
        mount "${DISK}2" /mnt 2>/dev/null || true
        mkdir -p /mnt/boot/efi 2>/dev/null || true
        mount "${DISK}1" /mnt/boot/efi 2>/dev/null || true
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
debootstrap unstable /mnt "$DEBIAN_URL" || true
arch-chroot /mnt /bin/bash <<'CHROOT2'
apt-get update || true
apt-get install -y linux-image-amd64 grub-efi-amd64 sudo bash nano less network-manager systemd udev locales || true
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Archy || true
update-grub || true
useradd -m -G sudo -s /bin/bash user || true
echo "user:archy" | chpasswd || true
echo "root:archy" | chpasswd || true
systemctl enable NetworkManager || true
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen || true
locale-gen || true
update-locale LANG=en_US.UTF-8 || true
CHROOT2
echo "Done. Unmount and reboot."
EOF
chmod +x /usr/bin/archy-install

# archy-init
cat > /usr/bin/archy-init <<'EOF'
#!/bin/bash
set -e
echo -e "\033[1;36mArchy Initialization\033[0m"
timedatectl set-ntp true || true
apt-get update || true
apt-get full-upgrade -y || true
dpkg-reconfigure locales || true
read -p "Enter hostname: " HOSTNAME
echo "$HOSTNAME" > /etc/hostname || true
echo -e "\033[1;32mInitialization complete!\033[0m"
EOF
chmod +x /usr/bin/archy-init

# archy-upgrade
cat > /usr/bin/archy-upgrade <<'EOF'
#!/bin/bash
set -e
echo -e "\033[1;34mArchy Upgrade System\033[0m"
apt-get update || true
apt-get full-upgrade -y || true
apt-get autoremove -y || true
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
update-grub || true

# Fix initramfs configuration
echo "COMPRESS=zstd" > /etc/initramfs-tools/conf.d/compression.conf
echo "MODULES=most" > /etc/initramfs-tools/conf.d/modules.conf
echo "DEVICE_MAPPER=no" > /etc/initramfs-tools/conf.d/dm.conf
update-initramfs -u -k all || true

# Live environment setup
mkdir -p /lib/live/config
cat > /lib/live/config/0030-archy <<'EOF'
#!/bin/sh
set -e
echo "archy-live" > /etc/hostname
cat > /etc/motd <<'MOTD'
Welcome to Archy Linux - The Minimalist's Dream
Type 'archy-help' for basic commands
MOTD
EOF
chmod +x /lib/live/config/0030-archy

# Create user
useradd -m -s /bin/bash user
echo "user:archy" | chpasswd
echo "root:archy" | chpasswd
CHROOT

# ---- UNMOUNT SYSTEM DIRECTORIES ----
echo "[4/6] Unmounting system directories..."
cleanup

# ---- ISO CREATION ----
echo "[5/6] Creating ISO structure..."
mkdir -p "$WORKDIR/iso"/{live,boot/grub,EFI/BOOT,boot/isolinux}

# Copy kernel files
VMLINUZ=$(find "$WORKDIR/boot" -name vmlinuz-* -print -quit)
INITRD=$(find "$WORKDIR/boot" -name initrd.img-* -print -quit)
[ -n "$VMLINUZ" ] && cp "$VMLINUZ" "$WORKDIR/iso/live/vmlinuz"
[ -n "$INITRD" ] && cp "$INITRD" "$WORKDIR/iso/live/initrd.img"

# Create GRUB configuration
cat > "$WORKDIR/iso/boot/grub/grub.cfg" <<'EOF'
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
grub-mkstandalone -O x86_64-efi -o "$WORKDIR/iso/EFI/BOOT/BOOTX64.EFI" "boot/grub/grub.cfg=$WORKDIR/iso/boot/grub/grub.cfg"

# Prepare BIOS boot files
mkdir -p "$WORKDIR/iso/boot/grub/i386-pc"
cp /usr/lib/grub/i386-pc/boot_hybrid.img "$WORKDIR/iso/boot/grub/i386-pc/"
cp /usr/lib/grub/i386-pc/eltorito.img "$WORKDIR/iso/boot/grub/i386-pc/"

# Create isolinux structure
cp /usr/lib/ISOLINUX/isolinux.bin "$WORKDIR/iso/boot/isolinux/"
cp /usr/lib/syslinux/modules/bios/* "$WORKDIR/iso/boot/isolinux/"

cat > "$WORKDIR/iso/boot/isolinux/isolinux.cfg" <<'EOF'
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

# ---- GENERATE ISO ----
echo "[6/6] Creating bootable ISO..."
xorriso -as mkisofs \
  -r -V "ARCHY_LIVE" \
  -o "$ISOFILE" \
  -J -joliet-long \
  -iso-level 3 \
  -partition_offset 16 \
  --grub2-mbr /usr/lib/grub/i386-pc/boot_hybrid.img \
  --mbr-force-bootable \
  -append_partition 2 0xEF "$WORKDIR/iso/EFI/BOOT/BOOTX64.EFI" \
  -appended_part_as_gpt \
  -c boot/isolinux/boot.cat \
  -b boot/isolinux/isolinux.bin \
  -no-emul-boot -boot-load-size 4 -boot-info-table \
  -eltorito-alt-boot \
  -e '--interval:appended_partition_2:all::' \
  -no-emul-boot \
  -isohybrid-gpt-basdat \
  "$WORKDIR/iso"

# ---- FINAL VERIFICATION ----
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
