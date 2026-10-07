#!/bin/bash

# Paths
HERE="$(dirname "$(readlink -f "${0}")")"
SCRIPT_PATH="${APPIMAGE:-$(readlink -f "$0")}"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
APPS_DIR="$HOME/.local/share/applications"
# Proton Paths
INTERNAL_PROTON_BASE="$HOME/.steam/steam/compatibilitytools.d/GE-Proton11-7/"
# Prefix Path
PROTON_PREFIX="$HOME/sharedprotonprefix/"


# Installation / Uninstallation Logic
if [[ "$1" == "--install" ]]; then
    mkdir -p "$APPS_DIR"
    echo "Installing desktop shortcuts and MIME types..."

    cat <<EOF > "$APPS_DIR/run-proton.desktop"
[Desktop Entry]
Name=Proton Launcher
Exec="$SCRIPT_PATH" %f
Icon=steam
Type=Application
Terminal=false
Categories=Utility
MimeType=application/x-ms-dos-executable;application/x-msi;application/x-msdownload;
EOF

    cat <<EOF > "$APPS_DIR/proton-explorer.desktop"
[Desktop Entry]
Name=Proton Explorer
Exec="$SCRIPT_PATH" explorer
Icon=folder-wine
Type=Application
Terminal=false
Categories=Utility;
EOF

    cat <<EOF > "$APPS_DIR/proton-winecfg.desktop"
[Desktop Entry]
Name=Proton Winecfg
Exec="$SCRIPT_PATH" winecfg
Icon=wine-winecfg
Type=Application
Terminal=false
Categories=Utility;
EOF

    cat <<EOF > "$APPS_DIR/proton-reboot.desktop"
[Desktop Entry]
Name=Proton Reboot (Kill)
Exec="$SCRIPT_PATH" wineboot -k
Icon=system-reboot
Type=Application
Terminal=false
Categories=Utility;
EOF

    cat <<EOF > "$APPS_DIR/proton-cmd.desktop"
[Desktop Entry]
Name=Proton Command Prompt
Exec="$SCRIPT_PATH" cmd
Icon=utilities-terminal
Type=Application
Terminal=false
Categories=Utility;
EOF

    cat <<EOF > "$APPS_DIR/proton-control.desktop"
[Desktop Entry]
Name=Proton Control Panel
Exec="$SCRIPT_PATH" control
Icon=preferences-system
Type=Application
Terminal=false
Categories=Utility;
EOF

    chmod +x "$APPS_DIR"/run-proton.desktop "$APPS_DIR"/proton-explorer.desktop "$APPS_DIR"/proton-winecfg.desktop "$APPS_DIR"/proton-reboot.desktop "$APPS_DIR"/proton-cmd.desktop "$APPS_DIR"/proton-control.desktop
    xdg-mime default run-proton.desktop application/x-ms-dos-executable
    xdg-mime default run-proton.desktop application/x-msi
    xdg-mime default run-proton.desktop application/x-msdownload
    update-desktop-database "$APPS_DIR" 2>/dev/null
    echo "Installation complete!"
    exit 0

elif [[ "$1" == "--uninstall" ]]; then
    echo "Removing shortcuts and resetting MIME types..."
    rm -f "$APPS_DIR/run-proton.desktop" "$APPS_DIR/proton-explorer.desktop" "$APPS_DIR/proton-winecfg.desktop" "$APPS_DIR/proton-reboot.desktop" "$APPS_DIR/proton-cmd.desktop" "$APPS_DIR/proton-control.desktop"
    xdg-mime uninstall "$APPS_DIR/run-proton.desktop" 2>/dev/null
    update-desktop-database "$APPS_DIR" 2>/dev/null
    echo "Uninstallation complete!"
    exit 0
fi

# Default Argument Logic
if [ -z "$1" ]; then
    set -- "explorer"
fi

# Path Resolution Logic
# If the first argument is a file (or a link to a file), resolve its real path.
if [ -f "$1" ]; then
    REAL_PATH=$(readlink -f "$1")
    # Shift the old path out and set the real path as the first argument
    shift
    set -- "$REAL_PATH" "$@"
    echo "Resolved shortcut/link to: $REAL_PATH"
fi


INTERNAL_PROTON_SCRIPT="$INTERNAL_PROTON_BASE/proton"

# Export Environment Variables
export WINEPREFIX="$PROTON_PREFIX/pfx"
export STEAM_COMPAT_DATA_PATH="$PROTON_PREFIX"
export STEAM_COMPAT_CLIENT_INSTALL_PATH="$HERE"
export WINEDLLPATH="$INTERNAL_PROTON_BASE/files/lib64/wine:$INTERNAL_PROTON_BASE/files/lib/wine"
export PROTON_DISABLE_LSTEAMCLIENT=1
export PROTON_NO_STEAM=1
export PROTON_USE_WOW64=1
export PROTON_MEDIA_USE_GST=1
export SDL_GAMECONTROLLER_IGNORE_DEVICES="$SDL_GAMECONTROLLER_IGNORE_DEVICES,0x057e/0x2009,0x057e/0x2006,0x057e/0x2007,0x0e6f/0x0180,0x0e6f/0x0184,0x0e6f/0x0185,0x0e6f/0x0188,0x20d6/0xa711,0x20d6/0xa712,0x20d6/0xa713"
export SDL_GAMECONTROLLER_ALLOW_STEAM_VIRTUAL_GAMEPAD=1
export SDL_GAMECONTROLLER_USE_BUTTON_LABELS=1
export GST_PLUGIN_SYSTEM_PATH_1_0="$GST_PLUGIN_SYSTEM_PATH_1_0:$HERE/opt/GE-Proton/files/lib/i386-linux-gnu/gstreamer-1.0/:$HERE/opt/GE-Proton/files/lib/x86_64-linux-gnu/gstreamer-1.0/:$HERE/opt/GE-Proton/files/lib/gstreamer-1.0/:$HERE/opt/GE-Proton/files/lib64/gstreamer-1.0/:$HERE/gstreamer-1.0/x86_64/:$HERE/gstreamer-1.0/i386/"
mkdir -p "$PROTON_PREFIX/gstreamer-1.0/"
export WINE_GST_REGISTRY_DIR="$PROTON_PREFIX/gstreamer-1.0/"

# Detect Steam Linux Runtime (SLR) entry point
SLR_ENTRY=""
UMU_SLR="$HOME/.local/share/umu/steamrt4/_v2-entry-point"
STEAM_SLR="$HOME/.local/share/Steam/steamapps/common/SteamLinuxRuntime_4/_v2-entry-point"

if [ -f "$UMU_SLR" ]; then
    SLR_ENTRY="$UMU_SLR"
elif [ -f "$STEAM_SLR" ]; then
    SLR_ENTRY="$STEAM_SLR"
fi

export PROTON_NO_ESYNC=0
export WINEESYNC=1
export PROTON_NO_FSYNC=0
export WINEFSYNC=1
export WINESYNC=1

# Prefix Creation
if [ ! -d "$PROTON_PREFIX/pfx" ]; then
    echo "Creating prefix structure at $PROTON_PREFIX/pfx..."
    mkdir -p "$PROTON_PREFIX/pfx"
fi

# Initial run check
if [ ! -f "$PROTON_PREFIX/tracked_files" ]; then
    echo "First run or prefix incomplete. Launching Proton..."
    if [ -f "$INTERNAL_PROTON_SCRIPT" ]; then
        if [ -n "$SLR_ENTRY" ]; then
            "$SLR_ENTRY" -- python3 "$INTERNAL_PROTON_SCRIPT" run winecfg
        else
            python3 "$INTERNAL_PROTON_SCRIPT" run winecfg
        fi
    fi
fi

# Execution Logic
echo "Launching Wine via Proton..."
if [ -f "$INTERNAL_PROTON_SCRIPT" ]; then
    if [ -n "$SLR_ENTRY" ]; then
        echo "Using Steam Linux Runtime: $SLR_ENTRY"
        exec "$SLR_ENTRY" -- python3 "$INTERNAL_PROTON_SCRIPT" run "$@"
    else
        echo "Steam Linux Runtime not found. Executing Proton directly..."
        exec python3 "$INTERNAL_PROTON_SCRIPT" run "$@"
    fi
else
    echo "Error: Internal Proton script not found at $INTERNAL_PROTON_SCRIPT"
    exit 1
fi
