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
sudo apt update || true
sudo apt upgrade -y || true
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
        echo "  [INFO] MetaTF 2.19.1 requires Python 3.12 (Kubuntu 25 defaults to 3.13)."
        echo "  [INFO] Setting up a local Python 3.12 interpreter just for this environment..."
        
        LOCAL_PY_DIR="$HOME/.local-python3.12"
        mkdir -p "$LOCAL_PY_DIR/deb"
        cd "$LOCAL_PY_DIR/deb"
        
        # Download Ubuntu 24.04 (Noble) packages of Python 3.12 to extract locally
        echo "  Downloading Python 3.12 packages..."
        wget -q -c http://security.ubuntu.com/ubuntu/pool/main/p/python3.12/python3.12-minimal_3.12.3-1ubuntu0.5_amd64.deb
        wget -q -c http://security.ubuntu.com/ubuntu/pool/main/p/python3.12/libpython3.12-minimal_3.12.3-1ubuntu0.5_amd64.deb
        wget -q -c http://security.ubuntu.com/ubuntu/pool/main/p/python3.12/libpython3.12-stdlib_3.12.3-1ubuntu0.5_amd64.deb
        wget -q -c http://security.ubuntu.com/ubuntu/pool/main/p/python3.12/python3.12-venv_3.12.3-1ubuntu0.5_amd64.deb
        
        echo "  Extracting packages locally..."
        for deb in *.deb; do
            dpkg -x "$deb" "$LOCAL_PY_DIR/extracted"
        done
        
        # Point PY_CMD to the locally extracted binary
        # We must set LD_LIBRARY_PATH so it finds its own extracted stdlib
        export LD_LIBRARY_PATH="$LOCAL_PY_DIR/extracted/usr/lib:${LD_LIBRARY_PATH:-}"
        export PYTHONPATH="$LOCAL_PY_DIR/extracted/usr/lib/python3.12"
        
        PY_CMD="$LOCAL_PY_DIR/extracted/usr/bin/python3.12"
        cd "$REPO_ROOT"
        
        if [ ! -f "$PY_CMD" ]; then
            echo "  [ERROR] Failed to extract local Python 3.12."
            exit 1
        fi
        echo "  [OK] Local Python 3.12 prepared at $PY_CMD"
    fi
fi

echo "  Selected Python interpreter: $PY_CMD"
# Try to ensure standard venv packages if using system python
if [[ "$PY_CMD" != *".local-python3.12"* ]]; then
    sudo apt install -y "${PY_CMD}-venv" "${PY_CMD}-dev" || true
fi

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
