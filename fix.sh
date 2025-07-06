#!/bin/bash

echo "🔒 Stopping SDDM..."
sudo systemctl stop sddm

echo "🔥 Purging KDE/Plasma-related packages..."
sudo apt purge sddm baloo* akonadi* libkf* libkworkspace* libplasma* kde* plasma* kwin* kio* kubuntu* -y
sudo apt autoremove --purge -y

echo "🧹 Removing user KDE/Plasma configs..."
rm -rf ~/.kde ~/.kde4 \
       ~/.config/k* ~/.config/plasma* ~/.config/kwin* \
       ~/.config/dolphin* ~/.config/akonadi* \
       ~/.config/xdg-desktop-portal-kde \
       ~/.local/share/k* ~/.local/share/plasma* \
       ~/.local/share/konsole ~/.local/share/kscreen \
       ~/.cache/ksycoca* ~/.cache/plasma* ~/.cache/kwin* ~/.cache/akonadi* \
       ~/.config/gtkrc* ~/.config/Trolltech.conf ~/.config/qt* \
       ~/.local/share/krunner ~/.local/share/RecentDocuments ~/.local/share/akonadi

echo "🧯 Removing system KDE configs and themes..."
sudo rm -rf /etc/xdg/k* /etc/xdg/plasma* /etc/xdg/kwin* \
            /etc/xdg/kscreenlockerrc /usr/share/k* /usr/share/plasma* \
            /usr/share/sddm/themes/* /usr/share/konsole /var/lib/sddm

echo "🔄 Updating APT..."
sudo apt update

echo "🚀 Reinstalling full Kubuntu desktop..."
sudo apt install kubuntu-desktop -y

echo "⚙️ Enabling SDDM..."
sudo systemctl enable sddm

echo "🔁 Rebooting now..."
sudo reboot