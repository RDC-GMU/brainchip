#!/bin/bash

echo "========================================"
echo " Brainchip AKD1000 M.2 Hardware Check"
echo "========================================"
echo ""

PASS=0
FAIL=0

# ──────────────────────────────────────────────
# Check 1: PCIe Bus
# Expected output: Co-processor: Device 1e7c:bca1 (rev 01)
# ──────────────────────────────────────────────
echo "1. Checking PCIe Bus (lspci)..."
PCI_OUTPUT=$(lspci | grep -iE "Co-processor|Brainchip|Akida" 2>/dev/null)

if [ -z "$PCI_OUTPUT" ]; then
    echo "   [FAIL] No Brainchip Akida device detected on the PCIe bus."
    echo "          - Power off and reseat the M.2 card firmly into its slot."
    echo "          - Check the slot is not sharing bandwidth with another card."
    FAIL=$((FAIL + 1))
else
    echo "   [PASS] Brainchip Akida device found on PCIe bus."
    echo "          $PCI_OUTPUT"
    PASS=$((PASS + 1))
fi
echo ""

# ──────────────────────────────────────────────
# Check 2: Kernel Module
# ──────────────────────────────────────────────
echo "2. Checking Akida kernel module (lsmod)..."
MODULE_OUTPUT=$(lsmod | grep akida 2>/dev/null)

if [ -z "$MODULE_OUTPUT" ]; then
    echo "   [FAIL] The 'akida-pcie' kernel module is not loaded."
    echo "          - Try: sudo modprobe akida-pcie"
    echo "          - If that fails, re-run: ./scripts/install_drivers.sh"
    FAIL=$((FAIL + 1))
else
    echo "   [PASS] Akida kernel module is loaded."
    echo "          $MODULE_OUTPUT"
    PASS=$((PASS + 1))
fi
echo ""

# ──────────────────────────────────────────────
# Check 3: Device node /dev/akida*
# ──────────────────────────────────────────────
echo "3. Checking device node (/dev/akida*)..."
DEVICE_FILES=$(ls /dev/akida* 2>/dev/null)

if [ -z "$DEVICE_FILES" ]; then
    echo "   [FAIL] No /dev/akida* device file found."
    echo "          - The driver may not have attached cleanly. Try: ./scripts/resetpcie.sh"
    FAIL=$((FAIL + 1))
else
    echo "   [PASS] Device node exists: $DEVICE_FILES"
    PASS=$((PASS + 1))
fi
echo ""

# ──────────────────────────────────────────────
# Check 4: akida devices (MetaTF CLI)
# Canonical check per official Brainchip install guide.
# Expected output: PCIe/NSoC_v2
# ──────────────────────────────────────────────
echo "4. Checking MetaTF hardware enumeration (akida devices)..."
if command -v akida &>/dev/null; then
    AKIDA_OUTPUT=$(akida devices 2>/dev/null)
    if echo "$AKIDA_OUTPUT" | grep -q "PCIe"; then
        echo "   [PASS] MetaTF can see the hardware device."
        echo "          $AKIDA_OUTPUT"
        PASS=$((PASS + 1))
    else
        echo "   [FAIL] 'akida devices' found no PCIe hardware."
        echo "          Output: $AKIDA_OUTPUT"
        echo "          - Ensure MetaTF >= 2.2.0 is installed (current recommended: 2.19.1)"
        echo "          - Try running as root to rule out a permissions issue: sudo akida devices"
        echo "          - If the device node vanished, run: ./scripts/resetpcie.sh"
        FAIL=$((FAIL + 1))
    fi
else
    echo "   [SKIP] 'akida' CLI not found. Is MetaTF installed in your active Python environment?"
    echo "          Activate your environment and re-run this script, or run: python tests/test_akida.py"
fi
echo ""

# ──────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────
echo "========================================"
echo " Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -eq 0 ]; then
    echo " All checks passed! Run: python tests/test_akida.py"
else
    echo " Some checks failed. Review messages above."
    echo " See docs/testing_guide.md for troubleshooting steps."
fi
echo "========================================"
