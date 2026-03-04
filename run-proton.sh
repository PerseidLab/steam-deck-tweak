#!/bin/bash

# --- 0. CONFIGURATION & PATHS ---
DESKTOP_DIR="$HOME/.local/share/applications"
MAIN_DESKTOP="run-proton.desktop"

EXTRA_DESKTOPS=("proton-explorer.desktop" "proton-winecfg.desktop" "proton-reboot.desktop" "proton-terminal.desktop" "proton-control.desktop")

# Paths to Proton and the Steam Linux Runtime (SLR)
PROTON_PATH="$HOME/.steam/steam/compatibilitytools.d/GE-Proton10-29"
RUNTIME_BASE="$HOME/.steam/steam/steamapps/common/SteamLinuxRuntime_sniper"

# Path to the Wine prefix
PREFIX_PATH="$HOME/sharedprotonprefix"
mkdir -p "$PREFIX_PATH"

# --- 1. SELF-INSTALLATION / UNINSTALLATION LOGIC ---

# UNINSTALL BLOCK
if [[ "$1" == "--uninstall" ]]; then
    echo "Reverting installation..."

    # Remove main runner
    rm -f "$DESKTOP_DIR/$MAIN_DESKTOP"

    # Remove the extra shortcuts (Now includes terminal)
    for file in "${EXTRA_DESKTOPS[@]}"; do
        if [ -f "$DESKTOP_DIR/$file" ]; then
            rm "$DESKTOP_DIR/$file"
            echo "Removed: $file"
        fi
    done

    update-desktop-database "$DESKTOP_DIR"
    echo "Uninstallation complete. .exe files will revert to system defaults."
    exit 0
fi

# INSTALL BLOCK
if [[ "$1" == "--install" ]]; then
    SCRIPT_PATH=$(realpath "$0")
    echo "Registering script and creating utility shortcuts..."

    mkdir -p "$DESKTOP_DIR"

    # A. Main EXE Runner
    cat <<EOF > "$DESKTOP_DIR/$MAIN_DESKTOP"
[Desktop Entry]
Type=Application
Name=Proton Runner
Comment=Run Windows EXEs via GE-Proton
Exec="$SCRIPT_PATH" %f
Icon=steam
Terminal=false
Categories=Utility;
MimeType=application/x-ms-dos-executable;application/x-msdownload;application/x-executable;
EOF

    # B. Wine Explorer Shortcut
    cat <<EOF > "$DESKTOP_DIR/proton-explorer.desktop"
[Desktop Entry]
Type=Application
Name=Proton Explorer
Comment=Open Wine File Browser for this prefix
Exec="$SCRIPT_PATH" explorer
Icon=folder-wine
Terminal=false
Categories=Utility;
EOF

    # C. Winecfg Shortcut
    cat <<EOF > "$DESKTOP_DIR/proton-winecfg.desktop"
[Desktop Entry]
Type=Application
Name=Proton Config
Comment=Change Wine settings for this prefix
Exec="$SCRIPT_PATH" winecfg
Icon=wine-winecfg
Terminal=false
Categories=Utility;
EOF

    # D. Wineboot (Kill) Shortcut
    cat <<EOF > "$DESKTOP_DIR/proton-reboot.desktop"
[Desktop Entry]
Type=Application
Name=Proton Kill/Reboot
Comment=Simulate a reboot or kill hung processes
Exec="$SCRIPT_PATH" wineboot -k
Icon=system-reboot
Terminal=false
Categories=Utility;
EOF

# E. Proton Terminal Shortcut
    cat <<EOF > "$DESKTOP_DIR/proton-terminal.desktop"
[Desktop Entry]
Type=Application
Name=Proton Terminal
Comment=Open a terminal inside the Proton environment
Exec=bash -c "$SCRIPT_PATH cmd"
Icon=utilities-terminal
Terminal=true
Categories=Utility;
EOF

    cat <<EOF > "$DESKTOP_DIR/proton-control.desktop"
[Desktop Entry]
Type=Application
Name=Proton Control Panel
Comment=Open a Control Panel inside the Proton environment
Exec=bash -c "$SCRIPT_PATH control"
Icon=preferences-system
Terminal=true
Categories=Utility;
EOF

    chmod +x "$DESKTOP_DIR"/*.desktop
    xdg-mime default "$MAIN_DESKTOP" application/x-ms-dos-executable
    xdg-mime default "$MAIN_DESKTOP" application/x-msdownload
    update-desktop-database "$DESKTOP_DIR"

    echo "Installation complete!"
    exit 0
fi

# --- 2. EXECUTION LOGIC ---

# Environment Variables
export STEAM_COMPAT_CLIENT_INSTALL_PATH="$HOME/.steam/steam"
export STEAM_COMPAT_DATA_PATH="$PREFIX_PATH"
export PROTON_VERB="run"
export PROTON_DISABLE_LSTEAMCLIENT=1
export PROTON_NO_STEAM=1
export PROTON_USE_WOW64=1
export PROTON_MEDIA_USE_GST=1
mkdir -p "$PREFIX_PATH/gstreamer-1.0/"
export WINE_GST_REGISTRY_DIR="$PREFIX_PATH/gstreamer-1.0/"
export SDL_JOYSTICK_HIDAPI=0
export SDL_HINT_JOYSTICK_HIDAPI=0

# Steam Runtime Integration
SNIPER_PLATFORM=$(ls -d "$RUNTIME_BASE"/sniper_platform_* 2>/dev/null | tail -n 1)
export PRESSURE_VESSEL_RUNTIME_ARCHIVE="$SNIPER_PLATFORM/files"

# If no argument is provided, default to explorer
if [ -z "$1" ]; then
    echo "No argument provided. Defaulting to Proton Explorer..."
    set -- "explorer"
fi

# --- SMART PATH HANDLING ---
# If the first argument is an existing file, treat it as an EXE runner
if [ -f "$1" ]; then
    EXE_PATH=$(realpath "$1")
    EXE_DIR=$(dirname "$EXE_PATH")
    cd "$EXE_DIR" || exit

    shift
    SET_ARGS=("$EXE_PATH" "$@")
else
    # Otherwise, treat arguments as direct wine commands (explorer, winecfg, etc.)
    SET_ARGS=("${@}")
fi

# --- 3. EXECUTE VIA THE RUNTIME ENTRY POINT ---
if [ -d "$RUNTIME_BASE" ]; then
    "$RUNTIME_BASE/run-in-sniper" -- "$PROTON_PATH/proton" run "${SET_ARGS[@]}"
else
    echo "Warning: Steam Runtime not found at $RUNTIME_BASE. Attempting direct execution..."
    "$PROTON_PATH/proton" run "${SET_ARGS[@]}"
fi
