echo "127.0.0.1 localhost archy" >> /etc/hosts
mount | grep "$CHROOT/dev/pts" >/dev/null || sudo mount -t devpts devpts "$CHROOT/dev/pts"
