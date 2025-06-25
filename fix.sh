sudo umount -lf archy-build/chroot/{dev,proc,sys} 2>/dev/null || true
sudo chattr -i -R archy-build 2>/dev/null || true
sudo rm -rf archy-build
