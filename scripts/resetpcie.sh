#!/bin/bash

echo "========================================"
echo " Brainchip AKD1000 PCIe Reset Utility"
echo "========================================"
echo ""

# Find the full PCI address (Domain:Bus:Device.Function) of the Brainchip device
PCI_ID=$(lspci -D | grep -iE "Co-processor.*Brainchip|Brainchip.*Co-processor|AKD1000" | awk '{print $1}')

if [ -z "$PCI_ID" ]; then
    echo "Error: Could not find Brainchip Akida device on the PCIe bus."
    echo "       Ensure the M.2 card is fully inserted and the system is powered."
    exit 1
fi

echo "Found Akida Co-processor at PCIe address: $PCI_ID"
echo ""

# ──────────────────────────────────────────────
# Step 1: Unload driver
# ──────────────────────────────────────────────
echo "Step 1: Unloading akida-pcie driver..."
sudo modprobe -r akida_pcie || true
sleep 1

# ──────────────────────────────────────────────
# Step 2: Remove and rescan the PCIe device
# ──────────────────────────────────────────────
echo "Step 2: Removing device from PCIe bus..."
sudo sh -c "echo 1 > /sys/bus/pci/devices/$PCI_ID/remove"
sleep 1

echo "Step 3: Rescanning PCIe bus..."
sudo sh -c "echo 1 > /sys/bus/pci/rescan"
sleep 2

# ──────────────────────────────────────────────
# Step 3: Reload driver
# ──────────────────────────────────────────────
echo "Step 4: Reloading akida-pcie driver..."
sudo modprobe akida_pcie

if [ $? -ne 0 ]; then
    echo ""
    echo "Error: Failed to reload the akida_pcie driver."
    echo "       Try running ./scripts/install_drivers.sh to reinstall."
    exit 1
fi
sleep 1

# ──────────────────────────────────────────────
# Step 4: Disable ASPM on the Akida device only
#
# The Jetson Orin Nano's NVMe SSD shares the same PCIe root complex
# as the M.2 slot. Disabling ASPM globally via the bootloader
# (pcie_aspm=off) BRICKS the Jetson by severing the NVMe link.
#
# Instead, we disable ASPM only on the Akida device's specific PCIe
# slot by writing 0x0000 to its Link Control register (CAP_EXP+10).
# This disables L0s and L1 ASPM states for this device only, and
# leaves the rest of the PCIe bus (including NVMe) untouched.
#
# NOTE: This setting resets on every reboot. To make it permanent,
# run this script (or add it to /etc/rc.local or a systemd service).
# ──────────────────────────────────────────────
echo "Step 5: Disabling ASPM on Akida device ($PCI_ID) only..."
sudo setpci -s "$PCI_ID" CAP_EXP+10.w=0000

if [ $? -eq 0 ]; then
    echo "        ASPM disabled for $PCI_ID (NVMe and other devices unaffected)."
else
    echo "        WARNING: setpci failed. The device may still time out."
    echo "        Ensure 'setpci' is installed: sudo apt install pciutils"
fi

echo ""
echo "========================================"
echo " PCIe reset complete."
echo " Run 'akida devices' to verify the card is enumerated."
echo "========================================"
