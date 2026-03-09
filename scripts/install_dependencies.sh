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
    echo "  Detected: NVIDIA Jetson (Tegra)"
else
    echo "  Detected: Standard Linux"
fi
echo ""

# ──────────────────────────────────────────────
# Step 1: System packages
# ──────────────────────────────────────────────
echo "Step 1: Updating system packages..."
sudo apt update
sudo apt upgrade -y
sudo apt install -y python3-pip python3-dev python3-venv build-essential

if [ "$IS_JETSON" = true ]; then
    echo "  Installing Jetson-specific system dependencies..."
    sudo apt install -y libhdf5-serial-dev hdf5-tools libjpeg8-dev
fi
echo ""

# ──────────────────────────────────────────────
# Step 2: Create virtual environment
# Note: --system-site-packages is used on Jetson so the venv can
# access any JetPack system-level Python bindings if needed.
# ──────────────────────────────────────────────
echo "Step 2: Setting up Python virtual environment at $VENV_DIR ..."

if [ -d "$VENV_DIR" ]; then
    echo "  Virtual environment already exists. Skipping creation."
else
    if [ "$IS_JETSON" = true ]; then
        python3 -m venv "$VENV_DIR" --system-site-packages
    else
        python3 -m venv "$VENV_DIR"
    fi
    echo "  Created: $VENV_DIR"
fi

VENV_PIP="$VENV_DIR/bin/pip"
echo ""

# ──────────────────────────────────────────────
# Step 3: Upgrade pip
# ──────────────────────────────────────────────
echo "Step 3: Upgrading pip..."
"$VENV_PIP" install --upgrade pip setuptools
echo ""

# ──────────────────────────────────────────────
# Step 4: Install TF-Keras + MetaTF
#
# The Akida AKD1000 is the ML inference co-processor — it handles all
# neural network execution in hardware. The host CPU only runs Python
# and does pre/post-processing. NVIDIA GPU-accelerated TensorFlow is
# NOT required on Jetson for Akida inference workloads.
#
# Standard tf-keras from PyPI works on both Jetson (aarch64) and x86.
# ──────────────────────────────────────────────
echo "Step 4: Installing TF-Keras and MetaTF packages..."
echo "  (Using standard CPU TF — the Akida card handles ML inference)"
echo ""

if [ -f "$REQUIREMENTS" ]; then
    "$VENV_PIP" install -r "$REQUIREMENTS"
else
    echo "  WARNING: requirements.txt not found at $REQUIREMENTS. Installing manually..."
    "$VENV_PIP" install tf-keras==2.19
    "$VENV_PIP" install akida==2.19.1
    "$VENV_PIP" install cnn2snn==2.19.1
    "$VENV_PIP" install akida-models==1.13.1
fi

echo ""
echo "=========================================="
echo " Installation complete!"
echo ""
echo " Activate your environment before running anything:"
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
