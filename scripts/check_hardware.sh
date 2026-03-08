#!/bin/bash

echo "========================================"
echo " Brainchip AKD1000 M.2 Hardware Check"
echo "========================================"
echo ""

echo "1. Checking PCIe Bus..."
PCI_OUTPUT=$(lspci | grep -iE "Co-processor|Brainchip|Akida" 2>/dev/null)

if [ -z "$PCI_OUTPUT" ]; then
    echo "Error: No Brainchip Akida device detected on the PCIe bus."
    echo "        Ensure the M.2 card is fully inserted into the slot and the system is powered."
    echo ""
else
    echo "Success: Brainchip Akida device found!"
    echo "   Details: $PCI_OUTPUT"
    echo ""
fi

echo "2. Checking Akida Kernel Module..."
MODULE_OUTPUT=$(lsmod | grep akida 2>/dev/null)

if [ -z "$MODULE_OUTPUT" ]; then
    echo "Error: The 'akida' kernel module is not loaded."
    echo "        Please install the driver and load it using 'sudo modprobe akida'."
    echo ""
else
    echo "Success: The 'akida' kernel module is loaded."
    echo "   Details: $MODULE_OUTPUT"
    echo ""
fi

echo "3. Checking Device File (/dev/akida*)..."
DEVICE_FILES=$(ls /dev/akida* 2>/dev/null)

if [ -z "$DEVICE_FILES" ]; then
    echo "Error: No device files found in /dev/."
    echo "        The driver may not have attached to the hardware cleanly."
    echo ""
else
    echo "Success: Device file(s) exist."
    echo "   Details: $DEVICE_FILES"
    echo ""
fi

echo "========================================"
echo "Check completed."
echo "If all steps above show 'Success', you can run 'python tests/test_akida.py' to test the MetaTF software stack."
echo "========================================"
