#!/bin/bash

echo "========================================"
echo " Brainchip Akida Driver Installation"
echo "========================================"
echo ""

set -e

TMP_DIR=$(mktemp -d)
DRIVER_REPO="https://github.com/Brainchip-Inc/akida_dw_edma"

echo "1. Installing Prerequisites..."
sudo apt update
if uname -r | grep -q "tegra"; then
    echo "Detected NVIDIA Jetson (Tegra). Installing L4T headers..."
    sudo apt install -y git build-essential nvidia-l4t-kernel-headers dkms
else
    sudo apt install -y git build-essential linux-headers-$(uname -r) dkms
fi

echo ""
echo "2. Cloning Driver Repository..."
echo "Cloning from $DRIVER_REPO..."
git clone $DRIVER_REPO $TMP_DIR

echo ""
echo "3. Building and Installing Driver..."
cd $TMP_DIR

if [ -f "./install.sh" ]; then
    chmod +x install.sh
    sudo ./install.sh
else
    echo "No install.sh found. Attempting manual make & make install..."
    make
    sudo make install
fi

echo ""
echo "4. Loading the 'akida' Module..."
sudo modprobe -r akida || true
sudo modprobe akida

echo ""
echo "5. Cleaning up..."
cd - > /dev/null
rm -rf $TMP_DIR

echo "========================================"
echo "Installation complete!"
echo "Run './scripts/check_hardware.sh' to verify the driver and hardware."
echo "========================================"
