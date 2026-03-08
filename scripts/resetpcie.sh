#!/bin/bash

echo "========================================"
echo " Brainchip AKD1000 PCIe Reset Utility"
echo "========================================"
echo ""

# ──────────────────────────────────────────────
# Find the Akida device PCI address
# ──────────────────────────────────────────────
PCI_ID=$(lspci -D | grep -iE "Co-processor.*Brainchip|Brainchip.*Co-processor|AKD1000" | awk '{print $1}')

if [ -z "$PCI_ID" ]; then
    echo "Error: Could not find Brainchip Akida device on the PCIe bus."
    echo "       Ensure the M.2 card is fully inserted and the system is powered."
    echo "       If the device was previously visible, try a full system reboot."
    exit 1
fi

echo "Found Akida Co-processor at: $PCI_ID"
echo ""

# ──────────────────────────────────────────────
# IMPORTANT: We do NOT remove/rescan the PCIe bus.
#
# On the NVIDIA Jetson Orin Nano (Tegra194 PCIe controller), doing a
# PCI bus remove + rescan causes the Tegra driver to reconfigure the
# ASPM common clock settings. This puts the BAR memory mapping into an
# inconsistent state, causing:
#   "akida-pcie: BAR I/O remapping failed (-22)"
# and preventing /dev/akida0 from being created.
#
# A simple driver unload + reload keeps the PCIe link and BAR
# assignments intact, and is the safe approach on Tegra.
# ──────────────────────────────────────────────

# ──────────────────────────────────────────────
# Step 1: Unload the driver
# ──────────────────────────────────────────────
echo "Step 1: Unloading akida_pcie driver..."
sudo modprobe -r akida_pcie 2>/dev/null || true
sleep 1

# ──────────────────────────────────────────────
# Step 2: Reload the driver
# The PCIe link stays up during this — BAR assignments are preserved.
# ──────────────────────────────────────────────
echo "Step 2: Reloading akida_pcie driver..."
sudo modprobe akida_pcie
sleep 1

if [ $? -ne 0 ]; then
    echo ""
    echo "Error: Failed to reload the akida_pcie driver."
    echo "       Try re-running: ./scripts/install_drivers.sh"
    echo "       Then reboot: sudo reboot"
    exit 1
fi

# ──────────────────────────────────────────────
# Step 3: Disable runtime power management
# Prevents the kernel from suspending the device via runtime PM,
# which can cause DMA timeouts.
# ──────────────────────────────────────────────
echo "Step 3: Disabling runtime PM for Akida device..."
if [ -f "/sys/bus/pci/devices/$PCI_ID/power/control" ]; then
    sudo sh -c "echo 'on' > /sys/bus/pci/devices/$PCI_ID/power/control"
    echo "  Runtime PM set to 'on' (always active) for $PCI_ID"
fi

# ──────────────────────────────────────────────
# Step 4: Verify /dev/akida* was created
# ──────────────────────────────────────────────
echo ""
DEVICE=$(ls /dev/akida* 2>/dev/null | head -1)
if [ -n "$DEVICE" ]; then
    echo "  [OK] Device node created: $DEVICE"
else
    echo "  [WARN] /dev/akida* not found after driver reload."
    echo "         Check 'sudo dmesg | grep -i akida' for errors."
    echo "         If BAR I/O remapping failed, a full reboot is required:"
    echo "         sudo reboot"
fi

echo ""
echo "========================================"
echo " Reset complete. Run 'akida devices' to verify."
echo "========================================"
