```bash
#!/bin/bash
set -Eeuo pipefail

echo "=== Reverting SteamOS Tweaks & Reconfiguring ZRAM (ram/2) ==="

ZRAM_CONF="/etc/systemd/zram-generator.conf"

echo "[1/10] Setting ZRAM to ram/2..."

sudo install -d /etc/systemd

sudo tee "$ZRAM_CONF" >/dev/null <<'EOF'
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
swap-priority = 100
fs-type = swap
EOF

sudo systemctl daemon-reload

echo "ZRAM configuration updated."
echo "A reboot may be required to recreate the ZRAM device."

SWAPFILE="/home/swapfile2"

echo "[2/10] Safely disabling and removing swapfile..."

if [[ -f "$SWAPFILE" ]]; then
    if sudo swapon --show=NAME --noheadings |
        grep -Fxq "$SWAPFILE"; then

        if ! sudo swapoff "$SWAPFILE"; then
            echo "ERROR: Could not disable $SWAPFILE."
            echo "The swapfile has NOT been deleted."
            exit 1
        fi
    fi

    sudo rm -f "$SWAPFILE"
    echo "Swapfile removed."
else
    echo "Swapfile does not exist; skipping."
fi

echo "[3/10] Removing swapfile entry from /etc/fstab..."

if [[ -f /etc/fstab ]]; then
    sudo sed -i '\|/home/swapfile2|d' /etc/fstab
fi

echo "[4/10] Removing swappiness override..."

sudo rm -f /etc/sysctl.d/99-swappiness.conf

echo "[5/10] Removing MGLRU configuration..."

sudo rm -f /etc/tmpfiles.d/mglru.conf
sudo rm -f /usr/local/sbin/configure-mglru
sudo rm -f /etc/systemd/system/configure-mglru.service

echo "[6/10] Removing memlock limits..."

sudo rm -f /etc/security/limits.d/memlock.conf

echo "[7/10] Removing ntsync module configuration..."

sudo rm -f /etc/modules-load.d/ntsync.conf

echo "[8/10] Restoring Transparent Huge Pages management..."

THP_SERVICE="/etc/systemd/system/disable-thp.service"

sudo systemctl disable --now disable-thp.service 2>/dev/null || true
sudo rm -f "$THP_SERVICE"

THP_ENABLED="/sys/kernel/mm/transparent_hugepage/enabled"
THP_DEFRAG="/sys/kernel/mm/transparent_hugepage/defrag"

if [[ -w "$THP_ENABLED" ]]; then
    echo always | sudo tee "$THP_ENABLED" >/dev/null ||
        echo "WARNING: Could not restore THP enabled setting."
fi

if [[ -w "$THP_DEFRAG" ]]; then
    echo always | sudo tee "$THP_DEFRAG" >/dev/null ||
        echo "WARNING: Could not restore THP defrag setting."
fi

echo "[9/10] Restoring CPU security mitigation configuration..."

GRUB_FILE="/etc/default/grub"

if [[ -f "$GRUB_FILE" ]] &&
    grep -qE '(^|[[:space:]])mitigations=off([[:space:]]|$)' "$GRUB_FILE"; then

    sudo sed -i \
        's/mitigations=off[[:space:]]*//g' \
        "$GRUB_FILE"

    echo "Removed mitigations=off from GRUB configuration."
    echo "SteamOS may not use this GRUB file for its active boot configuration."
else
    echo "No mitigations=off setting found in the GRUB file."
fi

echo "[10/10] Reloading system configuration..."

sudo systemctl daemon-reload
sudo sysctl --system

echo
echo "========================================"
echo " REVERT STATUS"
echo "========================================"

echo
echo "ZRAM configuration:"
cat "$ZRAM_CONF"

echo
echo "Active swap devices:"
swapon --show

echo
echo "Swappiness:"
sysctl vm.swappiness || true

echo
echo "THP enabled:"
cat /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true

echo
echo "THP defrag:"
cat /sys/kernel/mm/transparent_hugepage/defrag 2>/dev/null || true

echo
echo "Re-enabling SteamOS readonly mode..."

sudo steamos-readonly enable

echo
echo "=== Revert complete. Reboot your Steam Deck to apply ZRAM changes. ==="
```
