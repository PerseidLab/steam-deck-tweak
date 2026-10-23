```bash
#!/bin/bash
set -e

echo "=== SteamOS ZRAM + 1GB Swapfile + Performance Tweaks Setup ==="

echo "[1/13] Disabling SteamOS readonly mode..."
sudo steamos-readonly disable

echo "[2/13] Removing zswap configuration service..."
ZSWAP_SERVICE="/etc/systemd/system/zswap-configure.service"
sudo systemctl stop zswap-configure.service || true
sudo systemctl disable zswap-configure.service || true
sudo rm -f "$ZSWAP_SERVICE"
sudo rm -f /usr/local/sbin/configure-zswap

ZRAM_CONF="/usr/lib/systemd/zram-generator.conf"
echo "[3/13] Writing zram-generator configuration..."
sudo tee "$ZRAM_CONF" > /dev/null <<'EOF'
[zram0]
zram-size = ram
compression-algorithm = zstd
swap-priority = 100
fs-type = swap
EOF

SWAPFILE="/home/swapfile2"
SWAPSIZE="1G"
TARGET_SIZE=$((1 * 1024 * 1024 * 1024))
FILESYSTEM=$(stat -f -c %T "$(dirname "$SWAPFILE")")

create_swapfile() {
    if [ "$FILESYSTEM" = "btrfs" ]; then
        if sudo btrfs filesystem mkswapfile --help >/dev/null 2>&1; then
            sudo btrfs filesystem mkswapfile --size "$SWAPSIZE" "$SWAPFILE"
        else
            sudo touch "$SWAPFILE"
            sudo chattr +C "$SWAPFILE"
            sudo fallocate -l "$SWAPSIZE" "$SWAPFILE"
            sudo mkswap "$SWAPFILE"
        fi
    else
        sudo fallocate -l "$SWAPSIZE" "$SWAPFILE" ||
            sudo dd if=/dev/zero of="$SWAPFILE" bs=1M count=1024 status=progress

        sudo chmod 600 "$SWAPFILE"
        sudo mkswap "$SWAPFILE"
    fi

    sudo chmod 600 "$SWAPFILE"
}

echo "[4/13] Creating 1GB swapfile..."

if [ ! -f "$SWAPFILE" ]; then
    create_swapfile
else
    CURRENT_SIZE=$(sudo stat -c %s "$SWAPFILE")

    if [ "$CURRENT_SIZE" -ne "$TARGET_SIZE" ]; then
        if sudo swapon --show=NAME --noheadings |
            grep -Fxq "$SWAPFILE"; then
            sudo swapoff "$SWAPFILE"
        fi

        sudo rm -f "$SWAPFILE"
        create_swapfile
    else
        echo "Swapfile is already 1GB."
    fi
fi

echo "[5/13] Enabling swapfile..."
if ! sudo swapon --show=NAME --noheadings |
    grep -Fxq "$SWAPFILE"; then
    sudo swapon "$SWAPFILE"
fi

FSTAB_LINE="$SWAPFILE none swap sw 0 0"
if ! grep -Fq "$SWAPFILE" /etc/fstab; then
    echo "[6/13] Adding swapfile to /etc/fstab..."
    echo "$FSTAB_LINE" | sudo tee -a /etc/fstab > /dev/null
else
    echo "[6/13] Swapfile already in /etc/fstab."
fi

SYSCTL_CONF="/etc/sysctl.d/99-swappiness.conf"
echo "[7/13] Setting vm.swappiness..."
sudo tee "$SYSCTL_CONF" > /dev/null <<'EOF'
vm.swappiness=99
EOF

echo "[8/13] Configuring MGLRU..."
sudo tee /etc/tmpfiles.d/mglru.conf > /dev/null <<'EOF'
w /sys/kernel/mm/lru_gen/enabled - - - - 7
w /sys/kernel/mm/lru_gen/min_ttl_ms - - - - 0
EOF

echo "[9/13] Configuring memlock limits..."
sudo install -d /etc/security/limits.d
sudo tee /etc/security/limits.d/memlock.conf > /dev/null <<'EOF'
- hard memlock 2147484
- soft memlock 2147484
EOF

echo "[10/13] Enabling ntsync kernel module..."
echo ntsync | sudo tee /etc/modules-load.d/ntsync.conf > /dev/null

echo "[11/13] OPTIONAL: Disable CPU security mitigations"
read -r -p "Disable mitigations (mitigations=off)? [y/N]: " MITIGATIONS_CHOICE

if [[ "$MITIGATIONS_CHOICE" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    GRUB_FILE="/etc/default/grub"

    if [ -f "$GRUB_FILE" ]; then
        if ! grep -q "mitigations=off" "$GRUB_FILE"; then
            echo "Applying mitigations=off to GRUB..."
            sudo sed -i 's/\bGRUB_CMDLINE_LINUX_DEFAULT="/&mitigations=off /' "$GRUB_FILE"
            sudo grub-mkconfig -o /boot/efi/EFI/steamos/grub.cfg ||
                echo "Warning: grub-mkconfig failed."
        else
            echo "mitigations=off already present in GRUB config."
        fi
    else
        echo "GRUB configuration not found; skipping."
    fi
fi

echo "[12/13] Configuring service to disable Transparent Huge Pages (THP)..."
THP_SERVICE="/etc/systemd/system/disable-thp.service"

sudo tee "$THP_SERVICE" > /dev/null <<'EOF'
[Unit]
Description=Disable Transparent Huge Pages (THP)
DefaultDependencies=no
After=sysfsutils.service

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'test ! -w /sys/kernel/mm/transparent_hugepage/enabled || echo never > /sys/kernel/mm/transparent_hugepage/enabled'
ExecStart=/bin/sh -c 'test ! -w /sys/kernel/mm/transparent_hugepage/defrag || echo never > /sys/kernel/mm/transparent_hugepage/defrag'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable disable-thp.service
sudo systemctl start disable-thp.service

echo "[13/13] Reloading services and checking status..."
sudo systemctl daemon-reload
sudo sysctl --system

echo "=== Setup complete. ==="

echo "THP status:"
cat /sys/kernel/mm/transparent_hugepage/enabled

echo "Swap status:"
swapon --show

echo "ZRAM status:"
if [ -r /sys/block/zram0/disksize ]; then
    cat /sys/block/zram0/disksize
else
    echo "zram0 not currently available; reboot may be required."
fi
```
