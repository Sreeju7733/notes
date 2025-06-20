#!/bin/bash
set -euo pipefail

# ---- CONFIG ----
DISTRO_NAME="Archy"
DISTRO_VERSION="1.0"
ARCH="${ARCH:-amd64}"
WORKDIR="${PWD}/archy-build-${ARCH}"
ISOFILE="${PWD}/${DISTRO_NAME}-${DISTRO_VERSION}-${ARCH}.iso"
DEBIAN_URL="http://deb.debian.org/debian"
BUILD_DATE=$(date +%Y-%m-%d)

# Ensure critical directories exist
sudo mkdir -p /dev/pts
sudo mount -t devpts devpts /dev/pts || true

# Enhanced cleanup with terminal handling
cleanup() {
    echo "[!] Cleaning up..."
    # Unmount in reverse order
    for mountpoint in run sys proc dev/pts dev; do
        mountpoint -q "${WORKDIR}/${mountpoint}" && sudo umount -lf "${WORKDIR}/${mountpoint}" 2>/dev/null
    done
    [[ -d "${WORKDIR}" ]] && sudo rm -rf "${WORKDIR}"
}

trap cleanup EXIT

# ---- DEPENDENCY CHECK ----
echo "[*] Checking dependencies..."
function ensure_pkg() {
    local pkg="$1" bin="$2"
    if ! command -v "${bin}" >/dev/null; then
        echo "Installing dependency: ${pkg}"
        # Use direct root shell if sudo fails
        if ! sudo -S apt-get update; then
            su -c "apt-get update && apt-get install -y ${pkg}"
        else
            sudo apt-get install -y "${pkg}"
        fi
    fi
}

# Install critical packages first
for pkg in debootstrap:xorriso:parted:dosfstools:grub2:isolinux:syslinux-common:grub-efi-amd64-bin; do
    ensure_pkg "${pkg%:*}" "${pkg#*:}"
done

# ---- BUILD PROCESS ----
echo "[1/6] Setting up workspace..."
sudo mkdir -p "${WORKDIR}"

echo "[2/6] Bootstrapping base system..."
sudo debootstrap \
    --arch="${ARCH}" \
    --variant=minbase \
    --include=apt,dpkg,systemd \
    unstable "${WORKDIR}" "${DEBIAN_URL}"

echo "[3/6] Mounting system directories..."
sudo mount --bind /dev "${WORKDIR}/dev"
sudo mount -t proc proc "${WORKDIR}/proc"
sudo mount -t sysfs sys "${WORKDIR}/sys"
sudo mount -t tmpfs tmpfs "${WORKDIR}/run"

echo "[4/6] Configuring system..."
sudo chroot "${WORKDIR}" /bin/bash <<'EOF'
set -e
export DEBIAN_FRONTEND=noninteractive

# Minimal package setup
apt-get update && apt-get install -y --no-install-recommends \
    linux-image-${ARCH} grub-pc systemd-sysv

# Clean up
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/*
EOF

echo "[5/6] Creating ISO structure..."
ISO_DIR="${WORKDIR}/iso"
sudo mkdir -p "${ISO_DIR}"/{boot/grub,live}
sudo cp ${WORKDIR}/boot/vmlinuz-* "${ISO_DIR}/live/vmlinuz"
sudo cp ${WORKDIR}/boot/initrd.img-* "${ISO_DIR}/live/initrd.img"

cat <<EOF | sudo tee "${ISO_DIR}/boot/grub/grub.cfg" >/dev/null
set default=0
set timeout=5
menuentry "Archy Linux" {
    linux /live/vmlinuz boot=live
    initrd /live/initrd.img
}
EOF

echo "[6/6] Generating ISO..."
sudo grub-mkrescue -o "${ISOFILE}" "${ISO_DIR}" --volid="ARCHY_LIVE"

echo -e "\n\033[1;32m✅ ISO created: ${ISOFILE}\033[0m"
