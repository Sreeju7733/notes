sudo tee /home/sreeju/os1/archy-build/chroot/etc/apt/sources.list <<EOF
deb http://deb.debian.org/debian sid main contrib non-free non-free-firmware
EOF
sudo chroot /home/sreeju/os1/archy-build/chroot
apt update

