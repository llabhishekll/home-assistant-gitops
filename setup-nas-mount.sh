#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

echo "====================================================="
echo "      Starting WD MyCloud NAS Mount Setup            "
echo "====================================================="
echo ""

# ---------------------------------------------------------
# Step 0: Gather User Input
# ---------------------------------------------------------
echo "Please provide your NAS connection details."
echo ""

read -p "Enter NAS IP Address [default: 192.168.0.1]: " NAS_IP
NAS_IP=${NAS_IP:-192.168.0.1}

# Request multiple shares separated by spaces
read -p "Enter NAS Share Names (space separated) [default: Public]: " NAS_SHARES
NAS_SHARES=${NAS_SHARES:-Public}

# Ask for a base directory instead of a specific share path
read -p "Enter Base Local Mount Point [default: /mnt/mycloud]: " BASE_MOUNT
BASE_MOUNT=${BASE_MOUNT:-/mnt/mycloud}

read -p "Enter NAS Username [default: sysadmin]: " NAS_USER
NAS_USER=${NAS_USER:-sysadmin}

read -s -p "Enter NAS Password: " NAS_PASSWORD
echo "" # Add a newline after silent password input

echo ""
echo "Configuration saved temporarily. Starting setup..."
echo "====================================================="

# ---------------------------------------------------------
# Step 1: Install Prerequisites
# ---------------------------------------------------------
echo "[1/4] Installing CIFS utilities..."
sudo apt-get install -y cifs-utils
echo "====================================================="

# ---------------------------------------------------------
# Step 2: Create Secure Credentials File
# ---------------------------------------------------------
echo "[2/4] Setting up secure credentials file..."
CRED_FILE="/etc/smbcredentials"

echo "username=$NAS_USER" | sudo tee "$CRED_FILE" > /dev/null
echo "password=$NAS_PASSWORD" | sudo tee -a "$CRED_FILE" > /dev/null
sudo chmod 600 "$CRED_FILE"

echo "Credentials saved and secured at $CRED_FILE."
echo "====================================================="

# ---------------------------------------------------------
# Step 3 & 4: Create Directories & Configure fstab Loop
# ---------------------------------------------------------
echo "[3/4] Configuring directories and persistent mounts..."

# Backup the current fstab file just in case
sudo cp /etc/fstab /etc/fstab.bak

# Loop through each share provided by the user
for SHARE in $NAS_SHARES; do
    MOUNT_POINT="$BASE_MOUNT/$SHARE"
    
    echo " -> Processing share: $SHARE"
    
    # Create the local directory for this specific share
    sudo mkdir -p "$MOUNT_POINT"
    
    # Define the fstab entry
    FSTAB_ENTRY="//${NAS_IP}/${SHARE} ${MOUNT_POINT} cifs credentials=${CRED_FILE},uid=1000,gid=1000,iocharset=utf8 0 0"

    # Check if the entry already exists to avoid duplication
    if grep -qF "//${NAS_IP}/${SHARE}" /etc/fstab; then
        echo "    Mount entry already exists in /etc/fstab. Skipping."
    else
        echo "$FSTAB_ENTRY" | sudo tee -a /etc/fstab > /dev/null
        echo "    Added to /etc/fstab."
    fi
done
echo "====================================================="

# ---------------------------------------------------------
# Step 5: Test the Configuration
# ---------------------------------------------------------
echo "[4/4] Testing mount configuration..."

# Trigger a mount of all filesystems in fstab to test new entries
sudo mount -a

# Verify each share is mounted correctly
for SHARE in $NAS_SHARES; do
    MOUNT_POINT="$BASE_MOUNT/$SHARE"
    
    if mountpoint -q "$MOUNT_POINT"; then
        echo "Success! $SHARE is mounted at $MOUNT_POINT."
    else
        echo "Error: $SHARE mount failed. Please check credentials and share name."
    fi
done
echo "====================================================="

echo "====================================================="
echo " Setup Complete! "
echo "====================================================="
echo "All shares will automatically reconnect whenever the server reboots."