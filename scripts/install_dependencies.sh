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
sudo apt install -y build-essential software-properties-common

echo "Step 1.1: Ensuring Python 3.10, 3.11, or 3.12 is available (MetaTF compatibility)..."
PY_CMD=""
for py in python3.12 python3.11 python3.10; do
    if command -v "$py" &>/dev/null; then
        PY_CMD="$py"
        break
    fi
done

if [ -z "$PY_CMD" ]; then
    echo "  Python 3.10-3.12 not found in PATH."
    echo "  Attempting to install Python 3.12 from standard repos..."
    sudo apt install -y python3.12 python3.12-venv python3.12-dev || true
    
    if command -v python3.12 &>/dev/null; then
        PY_CMD="python3.12"
    else
        echo "  [ERROR] MetaTF 2.19.1 does not support Python 3.13+ yet, and"
        echo "  no older Python versions could be installed via apt."
        echo ""
        echo "  Please use Miniconda to create an environment with a supported Python version:"
        echo "    wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh"
        echo "    bash Miniconda3-latest-Linux-x86_64.sh -b -p \$HOME/miniconda3"
        echo "    source \$HOME/miniconda3/bin/activate"
        echo "    conda create -y -n akida_env python=3.12"
        echo "    conda activate akida_env"
        echo "    pip install tf-keras==2.19 akida==2.19.1 cnn2snn==2.19.1 akida-models==1.13.1"
        exit 1
    fi
fi

echo "  Selected Python interpreter: $PY_CMD"
# Ensure the venv and dev packages for the selected version are installed
sudo apt install -y "${PY_CMD}-venv" "${PY_CMD}-dev" || true

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
        $PY_CMD -m venv "$VENV_DIR" --system-site-packages
    else
        $PY_CMD -m venv "$VENV_DIR"
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
