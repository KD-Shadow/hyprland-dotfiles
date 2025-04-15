#!/bin/bash

set -e

echo "=== Arch Linux Installer ==="
read -p "Enter hostname: " HOSTNAME
read -p "Enter username: " USERNAME
read -s -p "Enter root password: " ROOT_PASSWORD
echo
read -s -p "Enter user password: " USER_PASSWORD
echo
read -p "Enter target disk (e.g. /dev/sda): " DISK

# === WIPE AND PARTITION DISK ===
sgdisk -Z $DISK
sgdisk -n1:0:+512M -t1:ef00 -c1:EFI $DISK
sgdisk -n2:0:0 -t2:8300 -c2:cryptroot $DISK

# Format EFI
mkfs.fat -F32 "${DISK}1"

# Encrypt root using root password
echo "[+] Encrypting ${DISK}2 with root password"
echo "$ROOT_PASSWORD" | cryptsetup luksFormat "${DISK}2" -
echo "$ROOT_PASSWORD" | cryptsetup open "${DISK}2" cryptroot -

# BTRFS format + subvols
mkfs.btrfs /dev/mapper/cryptroot

mount /dev/mapper/cryptroot /mnt
btrfs su cr /mnt/@
btrfs su cr /mnt/@home
btrfs su cr /mnt/@var
btrfs su cr /mnt/@snapshots
umount /mnt

mount -o noatime,compress=zstd,subvol=@ /dev/mapper/cryptroot /mnt
mkdir -p /mnt/{boot,home,var,.snapshots}
mount -o noatime,compress=zstd,subvol=@home /dev/mapper/cryptroot /mnt/home
mount -o noatime,compress=zstd,subvol=@var /dev/mapper/cryptroot /mnt/var
mount -o noatime,compress=zstd,subvol=@snapshots /dev/mapper/cryptroot /mnt/.snapshots
mount "${DISK}1" /mnt/boot

# === INSTALL BASE SYSTEM ===
pacstrap /mnt base linux linux-firmware intel-ucode \
    btrfs-progs grub sudo efibootmgr os-prober \
    hyprland waybar alacritty \
    networkmanager make debugedit \
    pipewire pipewire-alsa pipewire-pulse wireplumber \
    neovim git base-devel curl zsh \
    xdg-desktop-portal xdg-desktop-portal-hyprland \
    wl-clipboard grim slurp \
    systemd-zram-generator

genfstab -U /mnt >> /mnt/etc/fstab

# === CHROOT CONFIGURATION ===
arch-chroot /mnt /bin/bash <<EOF
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
hwclock --systohc

echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

echo "$HOSTNAME" > /etc/hostname
cat <<HOSTS > /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
HOSTS

# Set root and user
echo "root:$ROOT_PASSWORD" | chpasswd
useradd -m -G wheel,audio,video,network -s /bin/zsh $USERNAME
echo "$USERNAME:$USER_PASSWORD" | chpasswd
echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers

# mkinitcpio: enable encryption + btrfs
sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect keyboard keymap consolefont modconf block encrypt filesystems btrfs fsck)/' /etc/mkinitcpio.conf
mkinitcpio -P

# GRUB with LUKS support
UUID=\$(blkid -s UUID -o value ${DISK}2)
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
sed -i "s|GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=\$UUID:cryptroot root=/dev/mapper/cryptroot rootflags=subvol=@\"|" /etc/default/grub
sed -i 's|#GRUB_ENABLE_CRYPTODISK=y|GRUB_ENABLE_CRYPTODISK=y|' /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg

systemctl enable NetworkManager
systemctl enable pipewire
systemctl enable wireplumber

# ZRAM setup
mkdir -p /etc/systemd/zram-generator.conf.d
cat <<ZRAMCONF > /etc/systemd/zram-generator.conf.d/zram.conf
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
ZRAMCONF

EOF

echo "✅ Arch installation complete!"
echo "Reboot into your new encrypted, Wayland-ready system 🚀"

