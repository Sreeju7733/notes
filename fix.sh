#!/bin/bash

echo "🚀 Starting full KDE wipe and LXQt deploy..."

# 1. Remove all KDE, Plasma, Kubuntu, and related packages
echo "🧼 Removing KDE and Kubuntu bloat..."
sudo apt purge '^kde' '^plasma' '^kubuntu' '^kwin' '^akonadi' '^baloo' '^kmail' '^kio' '^kcm' '^kscreenlocker' '^okular' '^kate' '^kdeconnect' '^kwayland' '^qt5' '^qt6' '^sddm-theme-' -y
sudo apt autoremove --purge -y
sudo apt clean

# 2. Remove KDE & Plasma user config files
echo "🧹 Cleaning KDE configs from home directory..."
rm -rf ~/.kde ~/.kde4 \
       ~/.config/k* ~/.config/plasma* ~/.config/kwin* \
       ~/.config/dolphin* ~/.config/akonadi* ~/.config/kscreenlocker* \
       ~/.local/share/k* ~/.local/share/plasma* ~/.local/share/akonadi* \
       ~/.cache/ksycoca* ~/.cache/plasma* ~/.cache/kwin* \
       ~/.config/qt* ~/.local/share/konsole ~/.local/share/krunner

# 3. Install minimal LXQt and SDDM
echo "📦 Installing LXQt + SDDM..."
sudo apt update
sudo apt install --no-install-recommends lxqt sddm pcmanfm-qt lxterminal -y
sudo systemctl enable sddm

# 4. Install and configure fingerprint login
echo "🔐 Setting up fingerprint login..."
sudo apt install fprintd libpam-fprintd -y
fprintd-enroll

# Add fingerprint to PAM (for SDDM)
echo "✍️ Editing PAM config for SDDM..."
sudo sed -i '1iauth sufficient pam_fprintd.so' /etc/pam.d/sddm

# 5. Install power management tools
echo "🔋 Installing power-saving tools..."
sudo apt install tlp powertop -y
sudo systemctl enable tlp
sudo tlp start

# 6. Optional: Install KDE tools you still like
echo "📁 Installing useful KDE tools..."
sudo apt install dolphin systemsettings -y

# 7. Done!
echo "✅ LXQt is now your minimal, stable desktop. KDE is gone. System is optimized. Reboot and select LXQt in SDDM!"