#!/bin/bash

echo "=========================================="
echo " Brainchip MetaTF Dependency Installer"
echo "=========================================="
echo ""

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
REQUIREMENTS="$REPO_ROOT/requirements.txt"
VENV_DIR="$HOME/akida_env"

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
    echo "  Detected NVIDIA Jetson (Tegra). Installing Jetson-specific system dependencies..."
    sudo apt install -y libhdf5-serial-dev hdf5-tools libjpeg8-dev
fi
echo ""

# ──────────────────────────────────────────────
# Step 2: Create virtual environment
# On Jetson: use --system-site-packages so the venv
#   inherits JetPack's CUDA/GPU Python bindings.
# On standard PC: use a clean isolated venv.
# ──────────────────────────────────────────────
echo "Step 2: Setting up Python virtual environment at $VENV_DIR ..."

if [ -d "$VENV_DIR" ]; then
    echo "  Virtual environment already exists. Skipping creation."
else
    if [ "$IS_JETSON" = true ]; then
        echo "  Creating venv with --system-site-packages (required for JetPack CUDA bindings)..."
        python3 -m venv "$VENV_DIR" --system-site-packages
    else
        echo "  Creating clean isolated venv..."
        python3 -m venv "$VENV_DIR"
    fi
    echo "  Created: $VENV_DIR"
fi

# Use the venv's pip directly — we cannot 'source activate' inside a script
# and have it persist, so we call the venv binaries explicitly.
VENV_PIP="$VENV_DIR/bin/pip"
VENV_PYTHON="$VENV_DIR/bin/python"

echo ""

# ──────────────────────────────────────────────
# Step 3: Upgrade pip inside the venv
# ──────────────────────────────────────────────
echo "Step 3: Upgrading pip inside the virtual environment..."
"$VENV_PIP" install --upgrade pip setuptools
echo ""

# ──────────────────────────────────────────────
# Step 4: Install TensorFlow + MetaTF
# ──────────────────────────────────────────────
echo "Step 4: Installing TensorFlow and MetaTF packages..."

if [ "$IS_JETSON" = true ]; then
    echo ""
    echo "  Jetson detected: Installing NVIDIA GPU-accelerated TensorFlow."
    echo "  (Standard 'pip install tensorflow' will NOT provide GPU support on Jetson.)"
    echo ""

    # Auto-detect JetPack major version
    JP_VERSION=$(dpkg -l | grep -oP "nvidia-jetpack\s+\K[0-9]+" | head -1 || echo "")
    if [ -z "$JP_VERSION" ]; then
        echo "  WARNING: Could not auto-detect JetPack version. Defaulting to jp/v61."
        echo "  If this fails, check https://developer.nvidia.com/embedded/jetpack"
        JP_INDEX="v61"
    else
        echo "  Detected JetPack major version: $JP_VERSION"
        JP_INDEX="v${JP_VERSION}1"
    fi

    NVIDIA_TF_INDEX="https://developer.download.nvidia.com/compute/redist/jp/${JP_INDEX}"
    echo "  Using NVIDIA TF index: $NVIDIA_TF_INDEX"
    echo ""

    # Install NVIDIA TF first, then MetaTF individually to prevent pip from
    # overwriting the GPU TF build with a generic PyPI version.
    "$VENV_PIP" install --extra-index-url "$NVIDIA_TF_INDEX" tensorflow
    echo ""
    "$VENV_PIP" install akida==2.19.1
    "$VENV_PIP" install cnn2snn==2.19.1
    "$VENV_PIP" install akida-models==1.13.1

else
    echo "  Standard (non-Jetson) system detected. Installing from requirements.txt..."
    if [ -f "$REQUIREMENTS" ]; then
        "$VENV_PIP" install -r "$REQUIREMENTS"
    else
        echo "  WARNING: requirements.txt not found. Falling back to manual install..."
        "$VENV_PIP" install tf-keras==2.19
        "$VENV_PIP" install akida==2.19.1
        "$VENV_PIP" install cnn2snn==2.19.1
        "$VENV_PIP" install akida-models==1.13.1
    fi
fi

echo ""
echo "=========================================="
echo " Installation complete!"
echo ""
echo " IMPORTANT: Activate your environment before running any scripts:"
echo "   source $VENV_DIR/bin/activate"
echo ""
echo " Next steps:"
if [ "$IS_JETSON" = true ]; then
    echo "   1. Activate env:         source $VENV_DIR/bin/activate"
    echo "   2. Install PCIe driver:  ./scripts/install_drivers.sh"
    echo "   3. Reboot:               sudo reboot"
    echo "   4. Activate env again:   source $VENV_DIR/bin/activate"  
    echo "   5. Verify hardware:      ./scripts/check_hardware.sh"
    echo "   6. Run tests:            python3 tests/test_akida.py"
else
    echo "   1. Activate env:         source $VENV_DIR/bin/activate"
    echo "   2. Run tests:            python tests/test_akida.py"
fi
echo "=========================================="
