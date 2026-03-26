#!/bin/bash

echo "=========================================="
echo " Brainchip AKD1000 Dependency Installer"
echo " Platform: Raspberry Pi 5"
echo "=========================================="
echo ""

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
REQUIREMENTS="$REPO_ROOT/requirements.txt"
VENV_DIR="$HOME/akida_env"

# ──────────────────────────────────────────────
# Step 1: System packages
# ──────────────────────────────────────────────
echo "Step 1: Updating system packages..."
sudo apt update || true
sudo apt upgrade -y || true
sudo apt install -y \
    build-essential software-properties-common \
    curl wget git \
    linux-headers-$(uname -r) \
    libopenblas-dev libatlas-base-dev \
    libjpeg-dev libpng-dev zlib1g-dev \
    libfreetype6-dev pkg-config \
    libhdf5-dev hdf5-tools \
    libgl1 libglib2.0-0 \
    libcamera-dev libcamera-apps 2>/dev/null || \
sudo apt install -y \
    build-essential software-properties-common \
    curl wget git \
    linux-headers-$(uname -r) \
    libopenblas-dev libatlas-base-dev \
    libjpeg-dev libpng-dev zlib1g-dev \
    libfreetype6-dev pkg-config \
    libhdf5-dev hdf5-tools \
    libgl1 libglib2.0-0 || true

echo ""

echo "Step 1.1: Ensuring Python 3.10, 3.11, or 3.12 is available (MetaTF requirement)..."
PY_CMD=""
for py in python3.12 python3.11 python3.10; do
    if command -v "$py" &>/dev/null; then
        PY_CMD="$py"
        break
    fi
done

if [ -z "$PY_CMD" ]; then
    echo "  Python 3.10–3.12 not found. Installing Python 3.12..."
    sudo apt install -y python3.12 python3.12-venv python3.12-dev || true
    if command -v python3.12 &>/dev/null; then
        PY_CMD="python3.12"
    else
        echo "  [ERROR] Could not install Python 3.12. MetaTF requires Python 3.10–3.12."
        exit 1
    fi
fi

echo "  Selected Python: $PY_CMD ($($PY_CMD --version))"
# Ensure venv and dev packages for the selected interpreter
sudo apt install -y "${PY_CMD}-venv" "${PY_CMD}-dev" || true
echo ""

# ──────────────────────────────────────────────
# Step 2: Create virtual environment
# ──────────────────────────────────────────────
echo "Step 2: Setting up Python virtual environment at $VENV_DIR ..."

if [ -d "$VENV_DIR" ]; then
    echo "  Virtual environment already exists. Skipping creation."
else
    $PY_CMD -m venv "$VENV_DIR"
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
# Step 4: Install all Python packages
#
# The AKD1000 is the ML inference co-processor — all neural network
# execution happens in hardware on the Akida chip. The Pi's CPU only
# runs Python pre/post-processing. GPU-accelerated TensorFlow is
# NOT required. Standard tf-keras from PyPI works on aarch64.
# ──────────────────────────────────────────────
echo "Step 4: Installing Python packages..."
echo "  (CPU-only tf-keras — AKD1000 handles ML inference)"
echo ""

if [ -f "$REQUIREMENTS" ]; then
    "$VENV_PIP" install -r "$REQUIREMENTS"
else
    echo "  WARNING: requirements.txt not found at $REQUIREMENTS. Installing manually..."
    "$VENV_PIP" install tf-keras==2.19
    "$VENV_PIP" install akida==2.19.1 cnn2snn==2.19.1 akida-models==1.13.1
    "$VENV_PIP" install numpy matplotlib Pillow
    "$VENV_PIP" install flask flask-socketio psutil
fi

echo ""
echo "=========================================="
echo " Installation complete!"
echo ""
echo " Activate your environment:"
echo "   source $VENV_DIR/bin/activate"
echo ""
echo " Next steps:"
echo "   1. Activate env:         source $VENV_DIR/bin/activate"
echo "   2. Install PCIe driver:  ./scripts/install_drivers.sh"
echo "   3. Reboot:               sudo reboot"
echo "   4. Activate env again:   source $VENV_DIR/bin/activate"
echo "   5. Verify hardware:      ./scripts/check_hardware.sh"
echo "   6. Run tests:            python3 tests/test_akida.py"
echo "   7. Object detection:     python3 tests/test_object_detection.py"
echo "   8. Launch dashboard:     python3 src/app.py"
echo ""
echo "   Dashboard: http://$(hostname -I | awk '{print $1}'):5000"
echo "=========================================="
