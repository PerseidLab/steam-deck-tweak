#!/usr/bin/env bash

sudo steamos-readonly disable

set -e

# Get directory where script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SRC_FILES=(
    "60-steam-input.rules"
    "60-steam-vr.rules"
)

DST_DIR="/usr/lib/udev/rules.d"

echo "Installing persistent udev rules to $DST_DIR ..."

for file in "${SRC_FILES[@]}"; do
    SRC="$SCRIPT_DIR/$file"
    DST="$DST_DIR/$file"

    if [[ ! -f "$SRC" ]]; then
        echo "Error: $SRC not found"
        exit 1
    fi

    echo "Copying $file ..."
    sudo cp "$SRC" "$DST"
    sudo chmod 644 "$DST"
done

echo "Reloading udev rules..."
sudo udevadm control --reload-rules
sudo udevadm trigger

echo "Done."
