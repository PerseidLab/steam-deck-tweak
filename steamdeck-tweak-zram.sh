#!/bin/bash
set -e

echo "=== SteamOS ZRAM + Performance Tweaks Setup ==="

# 1. Disable readonly filesystem
echo "[1/13] Disabling SteamOS readonly mode..."
sudo steamos-readonly disable

# 2. Disable and Remove ZSWAP Service
echo "[2/13] Removing zswap configuration service..."
ZSWAP_SERVICE="/etc/systemd/system/zswap-configure.service"
sudo systemctl stop zswap-configure.service || true
sudo systemctl disable zswap-configure.service || true
sudo rm -f "$ZSWAP_SERVICE"

# 3. Configure zram-generator
ZRAM_CONF="/usr/lib/systemd/zram-generator.conf"
echo "[3/13] Writing zram-generator configuration..."
sudo tee "$ZRAM_CONF" > /dev/null <<EOF
[zram0]
zram-size = ram
compression-algorithm = zstd
swap-priority = 100
fs-type = swap
EOF

# 4. Create swapfile
SWAPFILE="/home/swapfile2"
# Get the filesystem type of the directory containing the swapfile
FILESYSTEM=$(stat -f -c %T "$(dirname "$SWAPFILE")")

if [ ! -f "$SWAPFILE" ]; then
    echo "[4/13] Creating 1GB swapfile on $FILESYSTEM..."

    if [ "$FILESYSTEM" == "btrfs" ]; then
        # Btrfs requires the file to be 0-length when setting +C (No CoW)
        sudo truncate -s 0 "$SWAPFILE"
        sudo chattr +C "$SWAPFILE"
        # Explicitly disable compression for this file
        sudo btrfs property set "$SWAPFILE" compression none
        # Now allocate the actual size
        sudo fallocate -l 16G "$SWAPFILE"
    else
        # Standard allocation for Ext4/XFS/other
        sudo fallocate -l 16G "$SWAPFILE" || sudo dd if=/dev/zero of="$SWAPFILE" bs=1G count=1 status=progress
    fi

    sudo chmod 600 "$SWAPFILE"
    sudo mkswap "$SWAPFILE"
else
    echo "[4/13] Swapfile already exists, skipping creation."
fi

# 5. Enable swapfile
echo "[5/13] Enabling swapfile..."
sudo swapon "$SWAPFILE" || true

# 6. Make swapfile persistent
FSTAB_LINE="$SWAPFILE none swap sw 0 0"
if ! grep -q "$SWAPFILE" /etc/fstab; then
    echo "[6/13] Adding swapfile to /etc/fstab..."
    # Note: On some immutable OSs, /etc/fstab is managed by the system.
    # This command will work if /etc is writable (as it usually is via overlay).
    echo "$FSTAB_LINE" | sudo tee -a /etc/fstab > /dev/null
else
    echo "[6/13] Swapfile already in /etc/fstab."
fi

# 7. Configure swappiness
SYSCTL_CONF="/etc/sysctl.d/99-swappiness.conf"
echo "[7/13] Setting vm.swappiness..."
sudo tee "$SYSCTL_CONF" > /dev/null <<EOF
vm.swappiness=99
EOF

# 8. Configure MGLRU
echo "[8/13] Configuring MGLRU..."
sudo tee /etc/tmpfiles.d/mglru.conf > /dev/null <<EOF
w /sys/kernel/mm/lru_gen/enabled - - - - 7
w /sys/kernel/mm/lru_gen/min_ttl_ms - - - - 0
EOF

# 9. Configure memlock limits
echo "[9/13] Configuring memlock limits..."
sudo tee /etc/security/limits.d/memlock.conf > /dev/null <<EOF
* hard memlock 2147484
* soft memlock 2147484
EOF

# 10. Enable ntsync kernel module
echo "[10/13] Enabling ntsync kernel module..."
echo ntsync | sudo tee /etc/modules-load.d/ntsync.conf > /dev/null

# 11. Disable CPU security mitigations
echo "[11/13] OPTIONAL: Disable CPU security mitigations"
read -r -p "Disable mitigations (mitigations=off)? [y/N]: " MITIGATIONS_CHOICE

if [[ "$MITIGATIONS_CHOICE" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    GRUB_FILE="/etc/default/grub"
    if ! grep -q "mitigations=off" "$GRUB_FILE"; then
        echo "Applying mitigations=off to GRUB..."
        sudo sed -i 's/\bGRUB_CMDLINE_LINUX_DEFAULT="/&mitigations=off /' "$GRUB_FILE"
        sudo grub-mkconfig -o /boot/efi/EFI/steamos/grub.cfg || echo "Warning: grub-mkconfig failed."
    else
        echo "mitigations=off already present in GRUB config."
    fi
fi

# 12. Disable Transparent Huge Pages (THP)
echo "[12/13] Configuring service to disable Transparent Huge Pages (THP)..."
THP_SERVICE="/etc/systemd/system/disable-thp.service"

sudo tee "$THP_SERVICE" > /dev/null <<EOF
[Unit]
Description=Disable Transparent Huge Pages (THP)
DefaultDependencies=no
After=sysfsutils.service

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo never > /sys/kernel/mm/transparent_hugepage/enabled'
ExecStart=/bin/sh -c 'echo never > /sys/kernel/mm/transparent_hugepage/defrag'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable disable-thp.service
sudo systemctl start disable-thp.service

# 13. Final Reload and Status
echo "[13/13] Reloading services and checking status..."
sudo systemctl daemon-reexec
sudo sysctl --system

echo "=== Setup complete. ==="
echo "THP status:"
cat /sys/kernel/mm/transparent_hugepage/enabled
