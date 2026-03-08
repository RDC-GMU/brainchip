#!/bin/bash

echo "=========================================="
echo " Brainchip MetaTF Dependency Installer"
echo "=========================================="
echo ""

set -e

IS_JETSON=false
if uname -r | grep -q "tegra"; then
    IS_JETSON=true
fi

# ──────────────────────────────────────────────
# Step 1: System packages
# ──────────────────────────────────────────────
echo "Step 1: Updating system packages..."
sudo apt update
sudo apt upgrade -y
sudo apt install -y python3-pip python3-dev python3-venv build-essential

if [ "$IS_JETSON" = true ]; then
    echo "Detected NVIDIA Jetson (Tegra). Installing Jetson-specific system dependencies..."
    sudo apt install -y libhdf5-serial-dev hdf5-tools libjpeg8-dev
fi

echo ""

# ──────────────────────────────────────────────
# Step 2: Upgrade pip
# ──────────────────────────────────────────────
echo "Step 2: Upgrading pip and setuptools..."
python3 -m pip install --upgrade pip setuptools
echo ""

# ──────────────────────────────────────────────
# Step 3: TensorFlow / TF-Keras
# ──────────────────────────────────────────────
echo "Step 3: Installing TensorFlow / TF-Keras..."

if [ "$IS_JETSON" = true ]; then
    echo ""
    echo "  !! Jetson detected: Installing NVIDIA's GPU-accelerated TensorFlow."
    echo "  !! Standard 'pip install tensorflow' will NOT provide GPU support on Jetson."
    echo ""
    echo "  Checking for JetPack version..."

    # Detect JetPack major version from dpkg
    JP_VERSION=$(dpkg -l | grep -oP "nvidia-jetpack\s+\K[0-9]+" | head -1 || echo "")

    if [ -z "$JP_VERSION" ]; then
        echo "  WARNING: Could not automatically detect JetPack version."
        echo "  Defaulting to JetPack 6.x index (jp/v61)."
        echo "  If this fails, check https://developer.nvidia.com/embedded/jetpack"
        echo "  and re-run with the correct index URL manually."
        JP_INDEX="v61"
    else
        echo "  Detected JetPack major version: $JP_VERSION"
        JP_INDEX="v${JP_VERSION}1"
    fi

    NVIDIA_TF_INDEX="https://developer.download.nvidia.com/compute/redist/jp/${JP_INDEX}"
    echo "  Using NVIDIA TF index: $NVIDIA_TF_INDEX"
    echo ""

    pip3 install --extra-index-url "$NVIDIA_TF_INDEX" tensorflow

    echo ""
    echo "Step 4: Installing MetaTF packages (individually to preserve Jetson TF build)..."
    pip3 install akida==2.19.1
    pip3 install cnn2snn==2.19.1
    pip3 install akida-models==1.13.1

else
    echo "  Standard (non-Jetson) system detected. Installing via requirements.txt..."
    echo ""

    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    REPO_ROOT="$(dirname "$SCRIPT_DIR")"
    REQUIREMENTS="$REPO_ROOT/requirements.txt"

    if [ -f "$REQUIREMENTS" ]; then
        pip3 install -r "$REQUIREMENTS"
    else
        echo "  WARNING: requirements.txt not found at $REQUIREMENTS"
        echo "  Falling back to manual install..."
        pip3 install tf-keras==2.19
        pip3 install akida==2.19.1
        pip3 install cnn2snn==2.19.1
        pip3 install akida-models==1.13.1
    fi
fi

echo ""
echo "=========================================="
echo " Dependency installation complete!"
echo " Next steps:"
if [ "$IS_JETSON" = true ]; then
    echo "   1. Install PCIe driver:  ./scripts/install_drivers.sh"
    echo "   2. Verify hardware:      ./scripts/check_hardware.sh"
    echo "   3. Run tests:            python3 tests/test_akida.py"
else
    echo "   1. Run tests:            python tests/test_akida.py"
fi
echo "=========================================="
