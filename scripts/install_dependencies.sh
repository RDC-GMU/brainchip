#!/bin/bash

echo "========================================"
echo " Updating System & Installing Dependencies"
echo "========================================"
echo ""

set -e

echo "1. System Update & Upgrade..."
sudo apt update
sudo apt upgrade -y

echo ""
echo "2. Installing Base Python & System Dependencies..."
sudo apt install -y python3-pip python3-dev python3-venv build-essential

if uname -r | grep -q "tegra"; then
    echo "Detected NVIDIA Jetson (Tegra). Installing Jetson-specific dependencies..."
    sudo apt install -y libhdf5-serial-dev hdf5-tools libjpeg8-dev
fi

echo ""
echo "3. Upgrading Pip and Setuptools..."
python3 -m pip install --user -U pip setuptools || pip3 install -U pip setuptools || echo "Ensure to upgrade pip manually if needed."

echo ""
echo "========================================"
echo "System Update & Dependency Installation complete!"
echo "Check the documentation (README.md or docs/jetson_orin_nano.md) for the next steps on installing TensorFlow and MetaTF."
echo "========================================"
