#!/bin/bash
set -euo pipefail

# === Config ===
export DISTRO_NAME="Archy"
export ARCH="${ARCH:-amd64}"
export WORKDIR="$PWD/archy-build-$ARCH"
export ISOFILE="$PWD/Archy-$ARCH.iso"
export DEBIAN_URL="http://deb.debian.org/debian"

# === Clean old build ===
sudo rm -rf "$WORKDIR"

echo "[1/5] 🧱 Creating minimal base system..."
sudo debootstrap \
    --arch="$ARCH" \
    --variant=minbase \
    --exclude=debian-archive-keyring,debian-faq,debian-reference \
    --include=apt,dpkg,linux-image-$ARCH \
    unstable "$WORKDIR" "$DEBIAN_URL"

# === System Config & Branding ===
echo "[2/5] 🎨 Configuring Archy system and branding..."

sudo chroot "$WORKDIR" /bin/bash <<'EOF'
set -e

# Remove Debian identity
apt purge -y debian-* os-prober tasksel reportbug || true
rm -rf /etc/{network,default,init.d,rc*.d,dpkg,apt/apt.conf.d}
rm -f /etc/{issue,issue.net,os-release,motd}

# Base packages
apt update
apt install -y --no-install-recommends \
    bash coreutils systemd udev sudo nano less grub2 \
    network-manager wget curl fdisk parted locales apt-listbugs

# APT sources
echo "deb http://deb.debian.org/debian unstable main" > /etc/apt/sources.list

# === archy-install ===
cat > /usr/bin/archy-install <<'INSTALL'
#!/bin/bash
set -e
echo -e "\033[1;36m"
cat <<'HEADER'
     _          _       
    /\  _ _ __| | ___ 
   / _ \| '/ _|  _/ -)
  // \\| \|\\| 

    ____            _         
   |  _ \ __ _ _ _| |_  ___ 
   | |) / _` | '| ' \/ __|
   |  _ < (| | |  | |) \__ \
   || \\,||  |./|/

      [ Powered by APT ]
HEADER
echo -e "\033[0m"

echo "Select disk to partition:"
lsblk
read -p "Disk (e.g. /dev/sda): " DISK

echo "Partition options:"
echo "1) Auto-partition"
echo "2) Manual"
read -p "Choice [1/2]: " CHOICE

case \$CHOICE in
    1)
        parted -s "\$DISK" mklabel gpt
        parted -s "\$DISK" mkpart primary 1MiB 513MiB
        parted -s "\$DISK" set 1 esp on
        parted -s "\$DISK" mkpart primary 513MiB 100%
        mkfs.fat -F32 "\${DISK}1"
        mkfs.ext4 "\${DISK}2"
        mount "\${DISK}2" /mnt
        mkdir -p /mnt/boot/efi
        mount "\${DISK}1" /mnt/boot/efi
        ;;
    2)
        cfdisk "\$DISK"
        echo "Mount root to /mnt and EFI to /mnt/boot/efi, then rerun."
        exit
        ;;
    *)
        echo "Invalid option"
        exit 1
        ;;
esac

debootstrap unstable /mnt http://deb.debian.org/debian

arch-chroot /mnt /bin/bash <<CHROOT
echo "Archy" > /etc/hostname
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
apt update
apt install -y linux-image-$ARCH grub-efi-$ARCH sudo bash nano less network-manager apt-listbugs

grub-install --target=${ARCH}-efi --efi-directory=/boot/efi --bootloader-id=Archy
echo 'GRUB_THEME="/boot/grub/themes/archy/theme.txt"' >> /etc/default/grub
update-grub

useradd -m -G sudo -s /bin/bash user
echo "user:password" | chpasswd
systemctl enable NetworkManager

echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
update-locale LANG=en_US.UTF-8

# === archy-init ===
cat > /usr/bin/archy-init <<'INIT'
#!/bin/bash
set -e
echo "Welcome to Archy Init"
timedatectl set-ntp true
apt update && apt upgrade -y
echo "System initialized."
INIT
chmod +x /usr/bin/archy-init

# === archy-upgrade ===
cat > /usr/bin/archy-upgrade <<'UPGRADE'
#!/bin/bash
set -e
echo -e "\033[1;34mArchy Upgrade Script - Stay Bleeding 🌊\033[0m"
echo "[*] Updating package lists..."
sudo apt update
echo "[*] Listing upgradable packages..."
apt list --upgradable
echo "[?] Do you want to upgrade your system now? (y/N)"
read -r confirm
if [[ "\$confirm" =~ ^[Yy]$ ]]; then
    echo "[] Performing full-upgrade (this *can break stuff)..."
    sudo apt full-upgrade -y
    echo "[✔] System upgraded. Reboot recommended."
else
    echo "[!] Upgrade cancelled. No changes made."
fi
UPGRADE
chmod +x /usr/bin/archy-upgrade

# === Aliases ===
echo "alias au='sudo archy-upgrade'" >> /etc/skel/.bashrc
echo "alias ai='sudo apt install'" >> /etc/skel/.bashrc
echo "alias ar='sudo apt remove'" >> /etc/skel/.bashrc
echo "alias as='apt search'" >> /etc/skel/.bashrc
echo "alias auh='apt update && apt list --upgradable'" >> /etc/skel/.bashrc

CHROOT

echo "Install complete. Reboot after removing media."
INSTALL
chmod +x /usr/bin/archy-install

# === GRUB Theme ===
mkdir -p /boot/grub/themes/archy
cp /background.png /boot/grub/themes/archy/
cp /logo.png /boot/grub/themes/archy/

cat > /boot/grub/themes/archy/theme.txt <<THEME
title-text: "Archy Linux"
title-color: "cyan"
desktop-image: "background.png"

+ boot_menu {
    left = 10%
    top = 45%
    width = 80%
    height = 35%
    item_height = 2
    item_padding = 1
    font = "DejaVuSans-12"
    selected_item_color = "white"
    item_color = "green"
    item_bg_color = "black"
    selected_item_bg_color = "cyan"
}

+ image {
    filename = "logo.png"
    x = 5%
    y = 5%
}
THEME

echo 'GRUB_THEME="/boot/grub/themes/archy/theme.txt"' >> /etc/default/grub
update-grub
EOF

# === ISO Creation ===
echo "[3/5] 📀 Creating ISO..."
sudo chroot "$WORKDIR" /bin/bash <<'EOF'
apt install -y --no-install-recommends syslinux isolinux live-boot

mkdir -p /iso/{boot/isolinux,live}
cp /boot/vmlinuz-* /iso/live/vmlinuz
cp /boot/initrd.img-* /iso/live/initrd.img

cat > /iso/boot/isolinux/isolinux.cfg <<EOL
DEFAULT archy
LABEL archy
  MENU LABEL Install Archy
  LINUX /live/vmlinuz
  INITRD /live/initrd.img
  APPEND boot=live components quiet splash
EOL

xorriso -as mkisofs -o /Archy.iso -b boot/isolinux/isolinux.bin \
  -c boot/isolinux/boot.cat -no-emul-boot -boot-load-size 4 \
  -boot-info-table -J -R /iso
EOF

# === Finalize ===
echo "[4/5] 🧹 Finalizing..."
sudo mv "$WORKDIR/Archy.iso" "$ISOFILE"
sudo rm -rf "$WORKDIR"

echo "[5/5] ✅ Archy ISO ready: $ISOFILE"
echo "💡 Test with: qemu-system-x86_64 -cdrom $ISOFILE -m 2G"
