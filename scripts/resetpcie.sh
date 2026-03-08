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
echo "Sending reset signal to /sys/bus/pci/devices/$PCI_ID/reset..."

# Trigger the PCIe bus reset
sudo sh -c "echo 1 > /sys/bus/pci/devices/$PCI_ID/reset"

if [ $? -eq 0 ]; then
    echo ""
    echo "Success: PCIe reset signal sent."
    echo "You should now be able to run 'python tests/test_akida.py' without timeout errors."
else
    echo ""
    echo "Error: Failed to reset the PCIe device. Please ensure you have sudo privileges."
    exit 1
fi
echo "========================================"
