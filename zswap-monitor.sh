#!/usr/bin/env bash

if [[ $EUID -ne 0 ]]; then
   echo "[-] Error: This script must be run as root (use sudo)." >&2
   exit 1
fi

# Paths for parameters and stats
MOD_DIR="/sys/module/zswap/parameters"
DBG_DIR="/sys/kernel/debug/zswap"

# Fallback check if debugfs is mounted
if [[ ! -d "$DBG_DIR" ]]; then
    mount -t debugfs debugfs /sys/kernel/debug 2>/dev/null
fi

read_val() {
    local path="$1"
    if [[ -f "$path" ]]; then
        cat "$path" 2>/dev/null
    else
        echo "0"
    fi
}

trap "tput cnorm; clear; exit 0" SIGINT SIGTERM
tput civis
clear

while true; do
    # Configuration from module parameters
    ENABLED=$(read_val "$MOD_DIR/enabled")
    COMPRESSOR=$(read_val "$MOD_DIR/compressor")
    MAX_POOL_PCT=$(read_val "$MOD_DIR/max_pool_percent")

    # Realtime stats from debugfs
    POOL_TOTAL_SIZE=$(read_val "$DBG_DIR/pool_total_size")
    STORED_PAGES=$(read_val "$DBG_DIR/stored_pages")
    SAME_FILLED=$(read_val "$DBG_DIR/same_filled_pages")
    WRITTEN_BACK=$(read_val "$DBG_DIR/written_back_pages")

    # Convert bytes to MB
    if [[ "$POOL_TOTAL_SIZE" =~ ^[0-9]+$ ]] && (( POOL_TOTAL_SIZE > 0 )); then
        POOL_SIZE_MB=$(awk "BEGIN {print $POOL_TOTAL_SIZE / 1024 / 1024}")
        # Compression ratio calculation (Uncompressed size / Compressed pool size)
        # Each stored page is normally 4096 bytes uncompressed
        UNCOMPRESSED_BYTES=$(( STORED_PAGES * 4096 ))
        COMP_RATIO=$(awk "BEGIN {printf \"%.2f\", $UNCOMPRESSED_BYTES / $POOL_TOTAL_SIZE}")
    else
        POOL_SIZE_MB="0.00"
        COMP_RATIO="0.00"
    fi

    tput cup 0 0
    cat << EOF
=====================================================
            STEAM DECK ZSWAP REAL-TIME MONITOR
=====================================================
 Refresh Rate: 2s | Press [Ctrl+C] to Exit
-----------------------------------------------------
 [Configuration]
   Status           : ${ENABLED}
   Compressor       : ${COMPRESSOR}
   Max Pool Percent : ${MAX_POOL_PCT}%

 [Statistics]
   Pool Size (RAM)  : ${POOL_SIZE_MB} MB (${POOL_TOTAL_SIZE} bytes)
   Stored Pages     : ${STORED_PAGES}
   Compression Ratio: ${COMP_RATIO}x
   Same-Filled Pages: ${SAME_FILLED}
   Written Back     : ${WRITTEN_BACK}
=====================================================
EOF

    sleep 2
done
