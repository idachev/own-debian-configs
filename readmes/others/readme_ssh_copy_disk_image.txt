
sudo dd if=/dev/sda | gzip -1 - | ssh 192.168.11.11 dd of=image.gz

