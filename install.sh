#!/usr/bin/env bash

echo "--------------------------------------------------"
echo "                 _             _                  "
echo "                / \   _ __ ___| |__               "
echo "               / _ \ | '__/ __| '_ \              "
echo "              / ___ \| | | (__| | | |             "
echo "             /_/   \_\_|  \___|_| |_|             "
echo "                                                  "
echo "--------------------------------------------------"

echo "--------------------------------------------------"
echo -e '\e[32m[0] Verify the boot mode\e[39m'
echo "--------------------------------------------------"
if [ -d /sys/firmware/efi ]; then
	BIOS_TYPE="uefi"
	echo "Install UEFI MODE"
else
	BIOS_TYPE="bios"
	echo "Install BIOS LEGACY MODE"
fi

echo "--------------------------------------------------"
echo -e '\e[32m[1] Update the system clock\e[39m'
echo "--------------------------------------------------"
timedatectl set-ntp true
timedatectl status

echo "--------------------------------------------------"
echo -e '\e[32m[2] Partition the disks\e[39m'
echo "--------------------------------------------------"
lsblk
echo -e '\e[33mSelect the disk:\e[39m'
select ENTRY in $(lsblk -dpnoNAME | grep -P '/dev/sd|nvme|vd'); do
	DISK=$ENTRY
	echo "Installing Arch Linux on $DISK"
	DISK1="${DISK}1"
	DISK2="${DISK}2"
	DISK3="${DISK}3"
	break
done
if swapon -s | grep "$DISK2" >/dev/null; then
	swapoff "$DISK2"
fi
if mountpoint -q /mnt; then
	umount -A --recursive /mnt
fi
wipefs -a -f "$DISK"
(
	echo n
	echo p
	echo
	echo
	echo +512M
	echo n
	echo p
	echo
	echo
	echo +16G
	echo n
	echo p
	echo
	echo
	echo
	echo w
) | fdisk "$DISK" -w always -W always

echo "--------------------------------------------------"
echo -e '\e[32m[3] Format the partitions\e[39m'
echo "--------------------------------------------------"
if [ "$BIOS_TYPE" == "uefi" ]; then
	mkfs.fat -F32 "$DISK1"
fi
if [ "$BIOS_TYPE" == "bios" ]; then
	mkfs.ext4 "$DISK1"
fi
mkswap "$DISK2"
mkfs.btrfs "$DISK3"
mount "$DISK3" /mnt
cd /mnt
btrfs subvolume create root
btrfs subvolume create home
btrfs subvolume create pkgs
btrfs subvolume create logs
btrfs subvolume create snapshots
cd ..
umount /mnt

echo "--------------------------------------------------"
echo -e '\e[32m[4] Mount the file systems\e[39m'
echo "--------------------------------------------------"
mount -o noatime,space_cache,compress-force=zstd,subvol=root "$DISK3" /mnt
mkdir -p /mnt/home
mkdir -p /mnt/var/cache/pacman
mkdir -p /mnt/var/log
mkdir -p /mnt/snapshots
mount -o noatime,space_cache,compress-force=zstd,subvol=home "$DISK3" /mnt/home
mount -o noatime,space_cache,compress-force=zstd,subvol=pkgs "$DISK3" /mnt/var/cache/pacman
mount -o noatime,space_cache,compress-force=zstd,subvol=logs "$DISK3" /mnt/var/log
mount -o noatime,space_cache,compress-force=zstd,subvol=snapshots "$DISK3" /mnt/snapshots
swapon "$DISK2"
if [ "$BIOS_TYPE" == "uefi" ]; then
	mkdir -p /mnt/boot/efi
	mount "$DISK1" /mnt/boot/efi
fi
if [ "$BIOS_TYPE" == "bios" ]; then
	mkdir -p /mnt/boot
	mount "$DISK1" /mnt/boot
fi

echo "--------------------------------------------------"
echo -e '\e[32m[5] Select the mirrors\e[39m'
echo "--------------------------------------------------"
reflector --age 48 --fastest 5 --latest 10 --protocol https --sort rate --save /etc/pacman.d/mirrorlist

echo "--------------------------------------------------"
echo -e '\e[32m[6] Install essential packages\e[39m'
echo "--------------------------------------------------"
sed -i "s/#Color/Color\nILoveCandy/" /etc/pacman.conf
sed -i "s/#ParallelDownloads/ParallelDownloads/" /etc/pacman.conf
pacstrap /mnt base base-devel linux-zen linux-zen-headers linux-firmware pacman-contrib
sed -i "s/#Color/Color\nILoveCandy/" /mnt/etc/pacman.conf
sed -i "s/#ParallelDownloads/ParallelDownloads/" /mnt/etc/pacman.conf

echo "--------------------------------------------------"
echo -e '\e[32m[7] Microcode\e[39m'
echo "--------------------------------------------------"
CPU=$(grep vendor_id /proc/cpuinfo)
if [[ "$CPU" == *"AuthenticAMD"* ]]; then
	arch-chroot /mnt pacman -S amd-ucode --noconfirm
fi
if [[ "$CPU" == *"GenuineIntel"* ]]; then
	arch-chroot /mnt pacman -S intel-ucode --noconfirm
fi

echo "--------------------------------------------------"
echo -e '\e[32m[8] Generate an fstab file\e[39m'
echo "--------------------------------------------------"
genfstab -U /mnt >>/mnt/etc/fstab

echo "--------------------------------------------------"
echo -e '\e[32m[9] Set the time zone\e[39m'
echo "--------------------------------------------------"
arch-chroot /mnt ln -sf /usr/share/zoneinfo/"$(curl -s http://ip-api.com/line?fields=timezone)" /etc/localtime
arch-chroot /mnt hwclock --systohc

echo "--------------------------------------------------"
echo -e '\e[32m[10] Localization\e[39m'
echo "--------------------------------------------------"
arch-chroot /mnt sed -i "s/#en_US.UTF-8/en_US.UTF-8/" /etc/locale.gen
arch-chroot /mnt locale-gen
arch-chroot /mnt localectl set-locale LANG=en_US.UTF-8
arch-chroot /mnt echo "export LANG=en_US.UTF-8" | tee -a /etc/profile
arch-chroot /mnt localectl status

echo "--------------------------------------------------"
echo -e '\e[32m[11] Network configuration\e[39m'
echo "--------------------------------------------------"
echo -e '\e[33mSet hostname:\e[39m'
read -r HOSTNAME
arch-chroot /mnt echo "$HOSTNAME" >/etc/hostname
arch-chroot /mnt cat >/etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain   $HOSTNAME
EOF

echo "--------------------------------------------------"
echo -e '\e[32m[12] Add user\e[39m'
echo "--------------------------------------------------"
arch-chroot /mnt pacman -S fish --noconfirm
echo -e '\e[33mSet username:\e[39m'
read -r USERNAME
arch-chroot /mnt useradd -m -G wheel -s /bin/fish "${USERNAME,,}"
echo -e '\e[33mSet user password:\e[39m'
arch-chroot /mnt passwd "${USERNAME,,}"
arch-chroot /mnt sed -i "s/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/" /etc/sudoers
arch-chroot /mnt pacman -S xdg-user-dirs --noconfirm
arch-chroot /mnt xdg-user-dirs-update
echo -e '\e[33mSet root password:\e[39m'
arch-chroot /mnt passwd

echo "--------------------------------------------------"
echo -e '\e[32m[13] Boot loader\e[39m'
echo "--------------------------------------------------"
if [ -d /sys/firmware/efi ]; then
	arch-chroot /mnt pacman -S btrfs-progs grub grub-btrfs efibootmgr --noconfirm
	arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
	arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
else
	arch-chroot /mnt pacman -S btrfs-progs grub grub-btrfs --noconfirm
	arch-chroot /mnt grub-install --target=i386-pc "$DISK"
	arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
fi
arch-chroot /mnt cat >/usr/share/libalpm/hooks/grub-update-after-kernel.hook <<EOF
[Trigger]
Operation = Install
Operation = Remove
Type = Package
Target = linux
Target = linux-lts
Target = linux-lts??
Target = linux-lts???
Target = linux-zen
Target = linux-hardened
Target = amd-ucode
Target = intel-ucode

[Action]
Description = Update grub after installing or removing a kernel or microcode.
When = PostTransaction
Depends = grub
Exec = /bin/sh -c "/usr/bin/grub-mkconfig -o /boot/grub/grub.cfg"
EOF

echo "--------------------------------------------------"
echo -e '\e[32m[14] Update packages\e[39m'
echo "--------------------------------------------------"
arch-chroot /mnt sed -i "s/#[multilib]/[multilib]/" /etc/pacman.conf
arch-chroot /mnt sed -i "s/#Include = /etc/pacman.d/mirrorlist/Include = /etc/pacman.d/mirrorlist/" /etc/pacman.conf
arch-chroot /mnt pacman -S reflector --noconfirm
arch-chroot /mnt reflector --age 48 --fastest 5 --latest 10 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
arch-chroot /mnt pacman -Syu

echo "--------------------------------------------------"
echo -e '\e[32m[15] Environment\e[39m'
echo "--------------------------------------------------"
arch-chroot /mnt echo "XAUTHORITY=${XDG_RUNTIME_DIR}/Xauthority" | tee -a /etc/environment

echo "--------------------------------------------------"
echo -e '\e[32m[16] Optimization\e[39m'
echo "--------------------------------------------------"
arch-chroot /mnt echo "vm.swappiness=10" >/etc/sysctl.d/99-swappiness.conf
arch-chroot /mnt sed -i "s/#MAKEFLAGS/MAKEFLAGS/" /etc/makepkg.conf
arch-chroot /mnt sed -i "s/-j2/-j$(nproc)/" /etc/makepkg.conf
arch-chroot /mnt sed -i "s/# %wheel ALL=(ALL) NOPASSWD: ALL/%wheel ALL=(ALL) NOPASSWD: ALL/" /etc/sudoers
arch-chroot /mnt pacman -S ufw gufw --noconfirm
arch-chroot /mnt systemctl enable ufw.service
arch-chroot /mnt ufw enable

echo "--------------------------------------------------"
echo -e '\e[32m[17] Xorg\e[39m'
echo "--------------------------------------------------"
arch-chroot /mnt pacman -S xorg --noconfirm

echo "--------------------------------------------------"
echo -e '\e[32m[18] Pipewire\e[39m'
echo "--------------------------------------------------"
arch-chroot /mnt pacman -S pipewire pipewire-alsa pipewire-pulse --noconfirm

echo "--------------------------------------------------"
echo -e '\e[32m[19] NetworkManager\e[39m'
echo "--------------------------------------------------"
arch-chroot /mnt pacman -S networkmanager --noconfirm
arch-chroot /mnt systemctl enable NetworkManager

echo "--------------------------------------------------"
echo -e '\e[32m[20] Bluetooth\e[39m'
echo "--------------------------------------------------"
arch-chroot /mnt pacman -S bluez bluez-utils --noconfirm
arch-chroot /mnt systemctl enable bluetooth.service

echo "--------------------------------------------------"
echo -e '\e[32m[21] Paru\e[39m'
echo "--------------------------------------------------"
arch-chroot /mnt pacman -S git --noconfirm
arch-chroot /mnt git clone https://aur.archlinux.org/paru-bin.git
arch-chroot /mnt cd paru-bin
arch-chroot /mnt makepkg -si --noconfirm
arch-chroot /mnt cd ..
arch-chroot /mnt rm -rf paru-bin/
# ARCH=$(uname -m)
# TAG=$(curl --silent "https://api.github.com/repos/Morganamilo/paru/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
# if [[ $ARCH == x86_64* ]]; then
# 	curl https://github.com/Morganamilo/paru/releases/download/${TAG}/paru-${TAG}-x86_64.tar.zst -o paru-${TAG}.tar.zst
# elif [[ $ARCH == arm* ]]; then
# 	curl https://github.com/Morganamilo/paru/releases/download/${TAG}/paru-${TAG}-aarch64.tar.zst -o paru-${TAG}.tar.zst
# fi
# arch-chroot /mnt pacman -U paru-${TAG}.tar.zst
# rm paru-${TAG}.tar.zst

echo "--------------------------------------------------"
echo -e '\e[32m[22] Fonts\e[39m'
echo "--------------------------------------------------"
arch-chroot /mnt pacman -S inter-font ttf-hack noto-fonts noto-fonts-cjk noto-fonts-emoji noto-fonts-extra adobe-source-sans-fonts ttf-dejavu ttf-droid ttf-inconsolata ttf-indic-otf ttf-liberation --noconfirm

echo "--------------------------------------------------"
echo -e '\e[32m[23] GNOME\e[39m'
echo "--------------------------------------------------"
arch-chroot /mnt pacman -S eog evince file-roller gdm gnome-backgrounds gnome-calculator gnome-control-center nautilus python-nautilus gnome-screenshot gnome-shell-extensions gnome-system-monitor gnome-terminal --noconfirm
arch-chroot /mnt systemctl enable gdm.service
arch-chroot /mnt sed -i "s/#WaylandEnable=false/WaylandEnable=false/" /etc/gdm/custom.conf

echo "--------------------------------------------------"
echo -e '\e[32m[24] Extra\e[39m'
echo "--------------------------------------------------"
arch-chroot /mnt pacman -S neovim git xsel xclip gnome-tweaks dconf-editor webp-pixbuf-loader p7zip unrar gvfs-gphoto2 gvfs-mtp sushi xdg-user-dirs-gtk --noconfirm

echo "--------------------------------------------------"
echo -e '\e[32m[25] Cleanup\e[39m'
echo "--------------------------------------------------"
arch-chroot /mnt sed -i "s/%wheel ALL=(ALL) NOPASSWD: ALL/# %wheel ALL=(ALL) NOPASSWD: ALL/" /etc/sudoers

echo "--------------------------------------------------"
echo -e '\e[32m[26] Remove install script\e[39m'
echo "--------------------------------------------------"
rm install.sh

echo "--------------------------------------------------"
echo -e '\e[32m[27] Reboot\e[39m'
echo "--------------------------------------------------"
umount -a
reboot
