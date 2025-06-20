#!/bin/bash
set -euo pipefail

# ---- CONFIG ----
DISTRO_NAME="Archy"
DISTRO_VERSION="1.0"
ARCH="${ARCH:-amd64}"
WORKDIR="/archy-build-${ARCH}"  # Using absolute path
ISOFILE="/${DISTRO_NAME}-${DISTRO_VERSION}-${ARCH}.iso"
DEBIAN_URL="http://deb.debian.org/debian"

# ---- TERMINAL FIX ----
fix_terminals() {
    # Create devpts if missing
    [ -d /dev/pts ] || mkdir -p /dev/pts
    mount | grep -q '/dev/pts' || mount -t devpts devpts /dev/pts 2>/dev/null || true
    
    # Fallback to direct root shell if sudo fails
    if ! sudo -n true 2>/dev/null; then
        echo "[WARN] Sudo not available, switching to direct root"
        exec su -c "$0 $*"
    fi
}
fix_terminals

# ---- DEPENDENCIES ----
install_deps() {
    local pkgs=(
        debootstrap
        xorriso
        grub2-common
        grub-efi-amd64-bin
        isolinux
    )
    
    if ! command -v apt-get >/dev/null; then
        echo "ERROR: This script requires Debian/Ubuntu"
        exit 1
    fi
    
    # Use direct apt-get to avoid sudo issues
    apt-get update
    for pkg in "${pkgs[@]}"; do
        dpkg -l | grep -q "^ii  ${pkg}" || apt-get install -y "$pkg"
    done
}

# ---- MAIN BUILD ----
main() {
    echo "[1/6] Preparing environment..."
    rm -rf "$WORKDIR" "$ISOFILE"
    mkdir -p "$WORKDIR"
    
    echo "[2/6] Bootstrapping base system..."
    debootstrap --arch="$ARCH" unstable "$WORKDIR" "$DEBIAN_URL"
    
    echo "[3/6] Mounting system directories..."
    mount -t proc proc "$WORKDIR/proc"
    mount -t sysfs sys "$WORKDIR/sys"
    mount --bind /dev "$WORKDIR/dev"
    
    echo "[4/6] Installing core packages..."
    chroot "$WORKDIR" /bin/bash <<'EOF'
set -e
apt-get update
apt-get install -y --no-install-recommends \
    linux-image-$ARCH \
    grub-efi-amd64 \
    systemd \
    network-manager
EOF
    
    echo "[5/6] Creating ISO structure..."
    mkdir -p "$WORKDIR/iso/boot/grub"
    cp -v "$WORKDIR"/boot/vmlinuz-* "$WORKDIR/iso/vmlinuz"
    cp -v "$WORKDIR"/boot/initrd.img-* "$WORKDIR/iso/initrd.img"
    
    cat > "$WORKDIR/iso/boot/grub/grub.cfg" <<EOF
set timeout=5
menuentry "Archy Linux" {
    linux /vmlinuz boot=live
    initrd /initrd.img
}
EOF
    
    echo "[6/6] Generating ISO..."
    grub-mkrescue -o "$ISOFILE" "$WORKDIR/iso"
    echo "✅ ISO created: $ISOFILE"
}

# ---- EXECUTION ----
if [ "$(id -u)" -eq 0 ]; then
    install_deps
    main
else
    echo "This script must be run as root"
    exit 1
fi
