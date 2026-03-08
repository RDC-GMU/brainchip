#!/bin/bash

echo "========================================"
echo " Brainchip Akida PCIe Driver Installer"
echo "========================================"
echo ""

set -e

DRIVER_REPO="https://github.com/Brainchip-Inc/akida_dw_edma"
CLONE_DIR="$HOME/akida_dw_edma"

# ──────────────────────────────────────────────
# Step 1: Install kernel headers & build tools
# ──────────────────────────────────────────────
echo "Step 1: Installing build prerequisites..."
sudo apt update
if uname -r | grep -q "tegra"; then
    echo "  Detected NVIDIA Jetson (Tegra). Installing L4T kernel headers..."
    sudo apt install -y git build-essential nvidia-l4t-kernel-headers dkms
else
    echo "  Standard Linux detected. Installing linux-headers..."
    sudo apt install -y git build-essential linux-headers-$(uname -r) dkms
fi

echo ""

# ──────────────────────────────────────────────
# Step 2: Clone the driver repository
# ──────────────────────────────────────────────
echo "Step 2: Cloning driver repository..."
echo "  Source: $DRIVER_REPO"

if [ -d "$CLONE_DIR" ]; then
    echo "  Existing clone found at $CLONE_DIR. Pulling latest..."
    git -C "$CLONE_DIR" pull
else
    git clone "$DRIVER_REPO" "$CLONE_DIR"
fi

echo ""

# ──────────────────────────────────────────────
# Step 3: Run the official install script
# Note: sudo ./install.sh handles all of the following automatically:
#   - Removing any old installed driver versions
#   - Building and installing the new driver via DKMS
#   - Configuring the module to load at every boot
#   - Setting udev rules so /dev/akida* is accessible to all users
# ──────────────────────────────────────────────
echo "Step 3: Running official Brainchip install script..."
cd "$CLONE_DIR"

if [ -f "./install.sh" ]; then
    chmod +x install.sh
    sudo ./install.sh
else
    echo "  WARNING: install.sh not found in cloned repository."
    echo "  Falling back to manual build..."
    make
    sudo make install
    sudo modprobe -r akida-pcie || true
    sudo modprobe akida-pcie
fi

echo ""
echo "========================================"
echo " Driver installation complete!"
echo ""
echo " Verify your setup:"
echo "   1. Check hardware:  ./scripts/check_hardware.sh"
echo "   2. Quick CLI check: akida devices"
echo "========================================"
