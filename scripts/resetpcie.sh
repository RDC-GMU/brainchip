#!/bin/bash

echo "========================================"
echo " Brainchip AKD1000 PCIe Reset Utility"
echo "========================================"
echo ""

# Find the full PCI address (Domain:Bus:Device.Function) of the Brainchip device
PCI_ID=$(lspci -D | grep -iE "Co-processor.*Brainchip|Co-processor.*Akida" | awk '{print $1}')

if [ -z "$PCI_ID" ]; then
    echo "Error: Could not find Brainchip Akida device on the PCIe bus."
    echo "Ensure the hardware is physically connected."
    exit 1
fi

echo "Found Akida Co-processor at PCIe address: $PCI_ID"
echo "Performing a full PCIe bus remove and rescan..."

# Unload the driver first
echo "Unloading akida-pcie driver..."
sudo modprobe -r akida-pcie || true

# Remove the device from the PCIe bus
echo "Removing device at $PCI_ID..."
sudo sh -c "echo 1 > /sys/bus/pci/devices/$PCI_ID/remove"
sleep 1

# Rescan the PCIe bus to wake up the slot
echo "Rescanning PCIe bus..."
sudo sh -c "echo 1 > /sys/bus/pci/rescan"
sleep 1

# Reload the driver
echo "Reloading akida-pcie driver..."
sudo modprobe akida-pcie

if [ $? -eq 0 ]; then
    echo ""
    echo "Success: Full PCIe device reset completed."
    echo "You should now be able to run 'python tests/test_akida.py' without timeout errors."
else
    echo ""
    echo "Error: Failed to reset the PCIe device. Please ensure you have sudo privileges."
    exit 1
fi
echo "========================================"
