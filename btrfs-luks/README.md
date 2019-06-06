Btrfs is a wonderful filesystem that is fully supported by LinuxMint.

But unfortunatly, out-of-the-box, the installer doesn't come with an easy solution to setup a btrfs filesystem fully encrypted with luks.

However, it is quite easy to make it by yourself.

What we will do is that we will prepare our partitions as we want them before the installation, we will mount them in /target, do the installation, and we will fix some files afterwards to tell the system what he needs to do on boot.
Pre-requisites:

    Download the LinuxMint ISO image
    Put it on a USB key with UnetBootIn
    Backup all your important data (/home, /var/lib/docker, etc...)
    Boot on the USB live system

Step 1: Disk Partitionning

Use gparted to make 4 partitions on your disk /dev/sda as follow:
- /dev/sda1 128M FAT32 flag:ESP,BOOT -> this will be our /boot/efi
- /dev/sda2 512M ext2 -> this will be our /boot
- /dev/sda3 16G ext2 -> this will be our encrypted luks-swap
- /dev/sda4 XXXG unformatted -> this will be our encrypted luks-btrfs, our / and /home and whatever subvolume we want

Notes: 1. I have 16G of RAM, so I use 16G of swap, change this value to be at least the same amount of RAM that you have in your system 2. Change XXX so you use your disk fully
Step 2: Prepare your encrypted partition

Open a terminal ,sudo to root, format the luks partition and open it

sudo -i  
cryptsetup luksFormat -h sha512 -c aes-xts-plain64 -s 512 -i 5000 /dev/sda4  
cryptsetup luksOpen /dev/sda4 crypt-btrfs  
mkfs.btrfs /dev/mapper/crypt-btrfs  

Step 3: install

launch the Install to disk application from the live system, follow the instructions, choose manual when asking for partitioning.
choose crypt-btrfs as / btrfs (do not choose format)
choose /dev/sda2 as /boot ext2 (choose format)
make sure that the /dev/sda1 is recognize as the EFI partition
do not choose swap, and ignore the message saying that you don't have swap
ignore other warning messages regarding your partitions

then, go on with the installation

at the end of the installation, DO NOT REBOOT
Step 4: mount again the filesystem and prepare for chroot

mount -o compress=lzo,ssd,noatime,discard,subvol=@ /dev/mapper/crypt-btrfs /mnt  
mount -o compress=lzo,ssd,noatime,discard,subvol=@home /dev/mapper/crypt-btrfs /mnt/home  
mount /dev/sda2 /mnt/boot  
mount /dev/sda1 /mnt/boot/efi  
mount --bind /proc /mnt/proc  
mount --bind /dev /mnt/dev  
mount --bind /sys /mnt/sys  
chroot /mnt  

Step 5: fixing the boot

Fist, take a look at the UUID of your partitions, open another terminal and do:
lsblk -f
then replace UUID-OF-/DEV/SDA4 with your UUID
and replace UUID-OF-/DEV/SDA2 with your UUID
and replace UUID-OF-/DEV/SDA1 with your UUID

vi /etc/crypttab  

your file should look like this:

/etc/crypttab:

crypt-btrfs /dev/disk/by-uuid/UUID-OF-/DEV/SDA4 none luks  
swapDevice /dev/sda3 /dev/urandom swap,cipher=aes-xts-plain64,size=256  

For the swap, it is better to use an absolute name like
"/dev/disk/by-id/ata-WDCWD2500BEVT-22ZCT0WD-WXE908VF0470-part",
you can find your own with
find -L /dev/disk -samefile /dev/sda3

chmod go-rx /etc/crypttab  
vi /etc/fstab  

/etc/fstab:

/dev/mapper/crypt-btrfs / btrfs device=/dev/mapper/crypt-btrfs,compress=lzo,noatime,ssd,discard,subvol=@ 0 1  
/dev/disk/by-uuid/UUID-OF-/DEV/SDA2 /boot ext3 defaults 0 2  
/dev/disk/by-uuid/UUID-OF-/DEV/SDA1 /boot/efi vfat umask=0077 0 1  
/dev/mapper/crypt-btrfs /home btrfs device=/dev/mapper/crypt-btrfs,noatime,compress=lzo,ssd,discard,subvol=@home 0 2  
/dev/mapper/swapDevice none swap sw 0 0  

Step 6: update your bootloader

open /etc/default/grub and remove "quiet splash" (it is easier to debug like this)
vi /etc/default/grub

and then:

update-initramfs -u -k all  
grub-install --recheck /dev/sda  
update-grub  

and reboot.
