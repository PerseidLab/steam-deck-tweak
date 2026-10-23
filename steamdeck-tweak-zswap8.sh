
#!/bin/bash
set -Eeuo pipefail

echo "=== SteamOS: ZRAM disabled + ZSWAP + Swapfile + Tweaks ==="

sudo steamos-readonly disable

echo "[2/12] Configuring zram-generator..."

sudo install -d /etc/systemd

sudo tee /etc/systemd/zram-generator.conf >/dev/null <<'EOF'
[zram0]
zram-size = 0
EOF

echo "[3/12] Configuring persistent systemd zswap service..."

sudo install -d /usr/local/sbin

sudo tee /usr/local/sbin/configure-zswap >/dev/null <<'EOF'
#!/bin/bash
set -Eeuo pipefail

PARAM=/sys/module/zswap/parameters

echo "Checking kernel zswap support..."

if [[ ! -d "$PARAM" || ! -r "$PARAM/enabled" ]]; then
    echo "ERROR: Kernel zswap parameters are unavailable."
    echo "Check whether this kernel supports zswap."
    exit 1
fi

if [[ -w "$PARAM/compressor" ]]; then
    CURRENT_COMPRESSOR=$(cat "$PARAM/compressor")

    if [[ "$CURRENT_COMPRESSOR" != "zstd" ]]; then
        if printf '%s\n' zstd > "$PARAM/compressor" 2>/dev/null; then
            echo "Compressor set to zstd."
        else
            echo "WARNING: Could not set zstd."
            echo "Keeping the kernel's current compressor."
        fi
    fi
fi

if [[ -w "$PARAM/max_pool_percent" ]]; then
    echo 25 > "$PARAM/max_pool_percent"
fi

if [[ "$(cat "$PARAM/enabled")" != "Y" ]]; then
    echo 1 > "$PARAM/enabled"
fi

if [[ "$(cat "$PARAM/enabled")" != "Y" ]]; then
    echo "ERROR: Failed to enable zswap."
    exit 1
fi

echo "Zswap configuration:"
for p in enabled compressor max_pool_percent; do
    if [[ -r "$PARAM/$p" ]]; then
        printf '  %s = %s\n' "$p" "$(cat "$PARAM/$p")"
    fi
done

echo "Zswap successfully enabled."
EOF

sudo chmod 755 /usr/local/sbin/configure-zswap

sudo tee /etc/systemd/system/zswap-configure.service >/dev/null <<'EOF'
[Unit]
Description=Enable and configure Linux zswap
After=systemd-modules-load.service local-fs.target
Before=swap.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/configure-zswap
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable zswap-configure.service
sudo systemctl restart zswap-configure.service



echo "[4/12] Creating 8GB swapfile if needed..."

SWAPFILE=/home/swapfile2
SWAPSIZE=8G
FILESYSTEM=$(findmnt -no FSTYPE -T /home)

if [[ ! -e "$SWAPFILE" ]]; then
    if [[ "$FILESYSTEM" == "btrfs" ]]; then
        if sudo btrfs filesystem mkswapfile --help >/dev/null 2>&1; then
            sudo btrfs filesystem mkswapfile --size "$SWAPSIZE" "$SWAPFILE"
        else
            echo "Creating Btrfs swapfile using fallback method..."
            sudo touch "$SWAPFILE"
            sudo chattr +C "$SWAPFILE"
            sudo fallocate -l "$SWAPSIZE" "$SWAPFILE"
            sudo mkswap "$SWAPFILE"
        fi
    else
        sudo fallocate -l "$SWAPSIZE" "$SWAPFILE" ||
            sudo dd if=/dev/zero of="$SWAPFILE" \
                bs=1M count=8192 status=progress

        sudo chmod 600 "$SWAPFILE"
        sudo mkswap "$SWAPFILE"
    fi
else
    CURRENT_SIZE=$(sudo stat -c %s "$SWAPFILE")
    TARGET_SIZE=$((8 * 1024 * 1024 * 1024))

    if [[ "$CURRENT_SIZE" -ne "$TARGET_SIZE" ]]; then
        echo "Existing swapfile is not 8GB."
        echo "Recreating it at 8GB."

        if sudo swapon --show=NAME --noheadings |
            grep -Fxq "$SWAPFILE"; then
            sudo swapoff "$SWAPFILE"
        fi

        sudo rm -f "$SWAPFILE"

        if [[ "$FILESYSTEM" == "btrfs" ]]; then
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
                sudo dd if=/dev/zero of="$SWAPFILE" \
                    bs=1M count=8192 status=progress

            sudo chmod 600 "$SWAPFILE"
            sudo mkswap "$SWAPFILE"
        fi
    else
        echo "Existing swapfile is already 8GB."
    fi
fi

sudo chmod 600 "$SWAPFILE"

echo "[5/12] Enabling swapfile..."

if ! sudo swapon --show=NAME --noheadings |
    grep -Fxq "$SWAPFILE"; then
    sudo swapon "$SWAPFILE"
fi


echo "[6/12] Configuring /etc/fstab..."

if ! grep -Fq "$SWAPFILE" /etc/fstab; then
    echo "$SWAPFILE none swap defaults 0 0" |
        sudo tee -a /etc/fstab >/dev/null
fi

echo "[7/12] Setting vm.swappiness=100..."

sudo tee /etc/sysctl.d/99-swappiness.conf >/dev/null <<'EOF'
vm.swappiness=100
EOF

sudo sysctl -w vm.swappiness=100

echo "[8/12] Configuring MGLRU..."

sudo tee /usr/local/sbin/configure-mglru >/dev/null <<'EOF'
#!/bin/bash
set -u

BASE=/sys/kernel/mm/lru_gen

if [[ -w "$BASE/enabled" ]]; then
    echo 7 > "$BASE/enabled"
else
    echo "MGLRU enabled control unavailable; skipping."
fi

if [[ -w "$BASE/min_ttl_ms" ]]; then
    echo 0 > "$BASE/min_ttl_ms"
fi
EOF

sudo chmod 755 /usr/local/sbin/configure-mglru

sudo tee /etc/systemd/system/configure-mglru.service >/dev/null <<'EOF'
[Unit]
Description=Configure Multi-Gen LRU
After=systemd-modules-load.service
Before=swap.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/configure-mglru
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable configure-mglru.service
sudo systemctl restart configure-mglru.service

echo "[9/12] Configuring memlock limits..."

sudo install -d /etc/security/limits.d

sudo tee /etc/security/limits.d/memlock.conf >/dev/null <<'EOF'
- hard memlock 2147484
- soft memlock 2147484
EOF

echo "[10/12] Configuring ntsync..."

if modinfo ntsync >/dev/null 2>&1; then
    echo ntsync |
        sudo tee /etc/modules-load.d/ntsync.conf >/dev/null

    sudo modprobe ntsync ||
        echo "ntsync will be retried at boot."
else
    echo "ntsync module not found; leaving it unconfigured."
fi

echo "[11/12] Configuring Transparent Huge Pages..."

sudo tee /etc/systemd/system/disable-thp.service >/dev/null <<'EOF'
[Unit]
Description=Disable Transparent Huge Pages
After=systemd-modules-load.service

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
sudo systemctl restart disable-thp.service

echo
echo "[12/12] OPTIONAL: Disable CPU security mitigations"
echo "WARNING: mitigations=off reduces security."
echo "SteamOS may not use /etc/default/grub for its active boot configuration."

read -r -p "Apply mitigations=off to GRUB if supported? [y/N]: " choice

if [[ "$choice" =~ ^([yY]|[yY][eE][sS])$ ]]; then
    GRUB_FILE=/etc/default/grub

    if [[ -f "$GRUB_FILE" ]]; then
        if ! grep -qE '(^|[[:space:]"])mitigations=off([[:space:]"]|$)' "$GRUB_FILE"; then
            sudo sed -i \
                '/^GRUB_CMDLINE_LINUX_DEFAULT=/ s/"$/ mitigations=off"/' \
                "$GRUB_FILE"
        fi

        echo "GRUB setting updated, if applicable."
        echo "Regenerate boot configuration only if your boot setup uses this GRUB file."
    else
        echo "GRUB configuration not found; skipping."
    fi
fi

echo
echo "Reloading systemd and sysctl..."

sudo systemctl daemon-reload
sudo sysctl --system

echo
echo "========================================"
echo " ZSWAP STATUS"
echo "========================================"

PARAM=/sys/module/zswap/parameters

if [[ -r "$PARAM/enabled" ]]; then
    printf 'Enabled: '
    cat "$PARAM/enabled"

    printf 'Compressor: '
    cat "$PARAM/compressor"

    printf 'Max pool percent: '
    cat "$PARAM/max_pool_percent"
else
    echo "ERROR: zswap parameters unavailable."
fi

echo
echo "========================================"
echo " SWAP STATUS"
echo "========================================"

swapon --show

echo
echo "========================================"
echo " ZRAM STATUS"
echo "========================================"

if [[ -d /sys/block/zram0 ]]; then
    cat /sys/block/zram0/disksize
else
    echo "No zram0 device detected."
fi

echo
echo "========================================"
echo " MGLRU STATUS"
echo "========================================"

if [[ -r /sys/kernel/mm/lru_gen/enabled ]]; then
    cat /sys/kernel/mm/lru_gen/enabled
else
    echo "MGLRU control unavailable."
fi

echo
echo "========================================"
echo " THP STATUS"
echo "========================================"

if [[ -r /sys/kernel/mm/transparent_hugepage/enabled ]]; then
    cat /sys/kernel/mm/transparent_hugepage/enabled
fi

echo
echo "========================================"
echo " ZSWAP SERVICE STATUS"
echo "========================================"

sudo systemctl --no-pager status zswap-configure.service || true

echo
echo "========================================"
echo " SETUP COMPLETE"
echo "========================================"
echo "After reboot, verify zswap with:"
echo "  cat /sys/module/zswap/parameters/enabled"
echo "  systemctl status zswap-configure.service"
