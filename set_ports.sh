#!/bin/bash

sudo steamos-readonly disable

# Define the config file path
CONF_FILE="/etc/sysctl.d/99-unprivileged-ports.conf"

echo "Setting unprivileged port start to 0..."

# 1. Check if running as root/sudo
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root. Try: sudo ./set_ports.sh"
   exit 1
fi

# 2. Create the configuration file
echo "net.ipv4.ip_unprivileged_port_start = 0" > "$CONF_FILE"

# 3. Apply the changes immediately
sysctl --system

echo "-------------------------------------------"
echo "Success! Low-numbered ports (under 1024) are now accessible to non-root users."
