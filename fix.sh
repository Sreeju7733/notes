sudo tee /home/sreeju/os1/archy-build/chroot/etc/apt/sources.list <<EOF
deb http://deb.debian.org/debian sid main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security sid-security main
EOF

sudo cp /etc/resolv.conf /home/sreeju/os1/archy-build/chroot/etc/resolv.conf

sudo chroot /home/sreeju/os1/archy-build/chroot
