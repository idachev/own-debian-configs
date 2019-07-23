#!/bin/bash

mount -o compress=lzo,ssd,noatime,discard,subvol=@ /dev/mapper/crypt-btrfs /mnt  

mount -o compress=lzo,ssd,noatime,discard,subvol=@home /dev/mapper/crypt-btrfs /mnt/home  

mount /dev/sda2 /mnt/boot  

mount /dev/sda1 /mnt/boot/efi  

mount --bind /proc /mnt/proc  
mount --bind /dev /mnt/dev  
mount --bind /sys /mnt/sys  

chroot /mnt  
