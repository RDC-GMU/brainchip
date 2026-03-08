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
    exit 1
fi

echo "Found Akida Co-processor at: $PCI_ID"

# Find the parent root port (one level up in sysfs)
PARENT_PCI=$(basename "$(dirname "$(readlink -f /sys/bus/pci/devices/$PCI_ID)")")
echo "Found parent PCIe root port at: $PARENT_PCI"
echo ""

# ──────────────────────────────────────────────
# Step 1: Unload driver
# ──────────────────────────────────────────────
echo "Step 1: Unloading akida_pcie driver..."
sudo modprobe -r akida_pcie 2>/dev/null || true
sleep 1

# ──────────────────────────────────────────────
# Step 2: Remove device from PCIe bus
# ──────────────────────────────────────────────
echo "Step 2: Removing device from PCIe bus..."
if [ -f "/sys/bus/pci/devices/$PCI_ID/remove" ]; then
    sudo sh -c "echo 1 > /sys/bus/pci/devices/$PCI_ID/remove"
else
    echo "  (Device already removed from bus)"
fi
sleep 1

# ──────────────────────────────────────────────
# Step 3: Rescan the PCIe bus
# ──────────────────────────────────────────────
echo "Step 3: Rescanning PCIe bus..."
sudo sh -c "echo 1 > /sys/bus/pci/rescan"
sleep 2

# ──────────────────────────────────────────────
# Step 4: Disable ASPM BEFORE loading the driver
#
# CRITICAL ORDER: setpci must happen BEFORE modprobe.
# If the driver loads first, it probes the device while ASPM is
# still active, causing a timeout during probe. The driver then
# fails to create /dev/akida0.
#
# ASPM is negotiated between TWO PCIe partners (endpoint + root port).
# We disable it on both sides to fully prevent the link from sleeping.
#
# Note: The Akida card is on domain 0004, a separate PCIe controller
# from the NVMe drive. Disabling ASPM here does NOT affect the NVMe.
# ──────────────────────────────────────────────
echo "Step 4: Disabling ASPM on Akida device and its root port..."
sudo setpci -s "$PCI_ID" CAP_EXP+10.w=0000
echo "  Disabled ASPM on endpoint: $PCI_ID"

if [ -n "$PARENT_PCI" ] && [ "$PARENT_PCI" != "pci0004:00" ]; then
    sudo setpci -s "$PARENT_PCI" CAP_EXP+10.w=0000
    echo "  Disabled ASPM on root port: $PARENT_PCI"
fi
sleep 1

# ──────────────────────────────────────────────
# Step 5: Load driver (ASPM now disabled — probe will succeed)
# ──────────────────────────────────────────────
echo "Step 5: Loading akida_pcie driver..."
sudo modprobe akida_pcie
sleep 1

if [ $? -ne 0 ]; then
    echo ""
    echo "Error: Failed to load the akida_pcie driver."
    echo "       Try re-running: ./scripts/install_drivers.sh"
    exit 1
fi

# ──────────────────────────────────────────────
# Step 6: Disable runtime power management
# Prevents the kernel from re-enabling ASPM via runtime PM
# ──────────────────────────────────────────────
echo "Step 6: Disabling runtime PM for Akida device..."
if [ -f "/sys/bus/pci/devices/$PCI_ID/power/control" ]; then
    sudo sh -c "echo 'on' > /sys/bus/pci/devices/$PCI_ID/power/control"
    echo "  Runtime PM set to 'on' (always active) for $PCI_ID"
fi

echo ""
echo "========================================"
echo " PCIe reset complete."
echo " Run 'akida devices' to verify the card is enumerated."
echo " NOTE: This fix resets on every reboot. Run this script again"
echo "       after rebooting, or set up a systemd service to automate it."
echo "========================================"
