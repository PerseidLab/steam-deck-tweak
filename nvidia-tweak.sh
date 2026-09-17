#!/bin/bash

ENV_FILE="/etc/environment"

VARIABLES=(
"export DXVK_CONFIG=\"dxvk.enableGraphicsPipelineLibrary = False\""
"export DXVK_STATE_CACHE=1"
"export DXVK_ASYNC=1"
"export __GL_SHADER_DISK_CACHE=1"
"export __GL_SHADER_DISK_CACHE_SKIP_CLEANUP=1"
"export __GL_SHADER_DISK_CACHE_SIZE=10737418240"
)

# Check for root/sudo privileges
if [ "$EUID" -ne 0 ]; then
  echo "Error: Please run this script as root or with sudo."
  exit 1
fi

echo "Adding DXVK and Nvidia configuration to $ENV_FILE..."

# Loop through and append each line if it doesn't already exist
for var in "${VARIABLES[@]}"; do
  if grep -Fxq "$var" "$ENV_FILE"; then
    echo "Skipping (already exists): $var"
  else
    echo "$var" >> "$ENV_FILE"
    echo "Added: $var"
  fi
done

echo "restart your system for changes to apply."
