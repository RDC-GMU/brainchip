#!/bin/bash
# ============================================================================
#  Brainchip AKD1000 — Jetson Orin PCIe ASPM Fix
#
#  Root cause: The Tegra PCIe root port independently manages ASPM and L1
#  sub-states, overriding the endpoint driver's pci_disable_link_state() call.
#  After the akida_pcie module probes, the root port puts the link back into
#  L1 sleep and the AKD1000 becomes unresponsive (Connection timed out).
#
#  This script:
#    1. Unloads the akida_pcie driver
#    2. Disables ASPM (L0s + L1) on BOTH the AKD1000 and its root port
#    3. Disables L1 sub-states (L1.1/L1.2) on both
#    4. Forces runtime PM to "always on" on both
#    5. Reloads the driver
#    6. Verifies /dev/akida0 was created
#
#  Usage:
#    sudo ./scripts/fix_jetson_pcie.sh
#
#  To run automatically at every boot, install the systemd service:
#    sudo cp scripts/akida-pcie-fix.service /etc/systemd/system/
#    sudo systemctl daemon-reload
#    sudo systemctl enable akida-pcie-fix.service
# ============================================================================

set -euo pipefail

echo "========================================"
echo " Brainchip AKD1000 Jetson PCIe ASPM Fix"
echo "========================================"
echo ""

# ── Must run as root ──────────────────────────────────────────────
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root (sudo)."
    exit 1
fi

# ── Step 0: Find the Akida endpoint and its root port ─────────────
echo "Step 0: Locating Akida device and root port..."

PCI_ID=$(lspci -D | grep -iE "Co-processor.*Brainchip|Brainchip.*Co-processor|AKD1000|Akida" | awk '{print $1}' | head -1)

if [ -z "$PCI_ID" ]; then
    echo "  [FAIL] No Brainchip Akida device found on the PCIe bus."
    echo "         Ensure the M.2 card is firmly seated. Try a full power cycle."
    exit 1
fi

echo "  Akida endpoint: $PCI_ID"

# Find the root port (parent bridge of the endpoint)
# Extract the domain:bus portion and look for the bridge at device 00.0
DOMAIN_BUS=$(echo "$PCI_ID" | sed 's/\(.*\):.*/\1/')
ROOT_PORT="${DOMAIN_BUS}:00.0"

# Verify root port exists
if ! lspci -s "$ROOT_PORT" &>/dev/null; then
    echo "  [WARN] Could not find root port at $ROOT_PORT, will skip root port config."
    ROOT_PORT=""
else
    echo "  Root port:      $ROOT_PORT"
fi
echo ""

# ── Step 1: Unload the driver ─────────────────────────────────────
echo "Step 1: Unloading akida_pcie driver..."
modprobe -r akida_pcie 2>/dev/null || true
sleep 1
echo "  Done."
echo ""

# ── Step 2: Disable ASPM on the endpoint ──────────────────────────
echo "Step 2: Disabling ASPM on Akida endpoint ($PCI_ID)..."

# Read PCIe Link Control register, clear ASPM bits [1:0]
LNKCTL=$(setpci -s "$PCI_ID" CAP_EXP+10.w 2>/dev/null || echo "")
if [ -n "$LNKCTL" ]; then
    LNKCTL_NEW=$(printf "%04x" $(( 0x$LNKCTL & 0xFFFC )))
    setpci -s "$PCI_ID" CAP_EXP+10.w="$LNKCTL_NEW"
    echo "  Link Control: 0x$LNKCTL -> 0x$LNKCTL_NEW (ASPM disabled)"
else
    echo "  [WARN] Could not read Link Control register on endpoint."
fi
echo ""

# ── Step 3: Disable ASPM on the root port ─────────────────────────
if [ -n "$ROOT_PORT" ]; then
    echo "Step 3: Disabling ASPM on root port ($ROOT_PORT)..."

    LNKCTL_RP=$(setpci -s "$ROOT_PORT" CAP_EXP+10.w 2>/dev/null || echo "")
    if [ -n "$LNKCTL_RP" ]; then
        LNKCTL_RP_NEW=$(printf "%04x" $(( 0x$LNKCTL_RP & 0xFFFC )))
        setpci -s "$ROOT_PORT" CAP_EXP+10.w="$LNKCTL_RP_NEW"
        echo "  Link Control: 0x$LNKCTL_RP -> 0x$LNKCTL_RP_NEW (ASPM disabled)"
    else
        echo "  [WARN] Could not read Link Control register on root port."
    fi
    echo ""
else
    echo "Step 3: Skipped (root port not found)."
    echo ""
fi

# ── Step 4: Disable L1 Sub-States ─────────────────────────────────
# L1 sub-states (L1.1 / L1.2) are controlled by a PCIe Extended Capability
# (ID 0x1E). We find its config-space offset and clear the enable bits in
# the L1SS Control 1 register (capability_offset + 0x08), bits [3:0].
echo "Step 4: Disabling L1 sub-states..."

disable_l1ss() {
    local DEV="$1"
    local LABEL="$2"

    # Find L1SS extended capability offset from lspci verbose output
    local L1SS_OFFSET
    L1SS_OFFSET=$(lspci -s "$DEV" -vvv 2>/dev/null \
        | grep -i "L1SubStates" \
        | grep -oP '\[([0-9a-fA-F]+)\]' \
        | head -1 \
        | tr -d '[]' || echo "")

    if [ -z "$L1SS_OFFSET" ]; then
        echo "  $LABEL ($DEV): No L1 Sub-States capability found (OK)."
        return
    fi

    # L1SS Control 1 register is at offset + 0x08
    local CTL1_OFFSET
    CTL1_OFFSET=$(printf "%03x" $(( 0x$L1SS_OFFSET + 0x08 )))

    local CTL1_VAL
    CTL1_VAL=$(setpci -s "$DEV" "$CTL1_OFFSET.l" 2>/dev/null || echo "")

    if [ -n "$CTL1_VAL" ]; then
        local CTL1_NEW
        CTL1_NEW=$(printf "%08x" $(( 0x$CTL1_VAL & 0xFFFFFFF0 )))
        setpci -s "$DEV" "$CTL1_OFFSET.l=$CTL1_NEW"
        echo "  $LABEL ($DEV): L1SS CTL1 0x$CTL1_VAL -> 0x$CTL1_NEW"
    else
        echo "  $LABEL ($DEV): Could not read L1SS Control register."
    fi
}

disable_l1ss "$PCI_ID" "Endpoint"
if [ -n "$ROOT_PORT" ]; then
    disable_l1ss "$ROOT_PORT" "Root port"
fi
echo ""

# ── Step 5: Force runtime PM to "on" ─────────────────────────────
echo "Step 5: Forcing runtime PM to 'always on'..."

SYSFS_EP="/sys/bus/pci/devices/$PCI_ID/power/control"
if [ -f "$SYSFS_EP" ]; then
    echo "on" > "$SYSFS_EP"
    echo "  Endpoint:  runtime PM = on"
fi

if [ -n "$ROOT_PORT" ]; then
    SYSFS_RP="/sys/bus/pci/devices/$ROOT_PORT/power/control"
    if [ -f "$SYSFS_RP" ]; then
        echo "on" > "$SYSFS_RP"
        echo "  Root port: runtime PM = on"
    fi
fi
echo ""

# ── Step 6: Reload the driver ─────────────────────────────────────
echo "Step 6: Loading akida_pcie driver..."
modprobe akida_pcie
sleep 2
echo "  Done."
echo ""

# ── Step 7: Verify ────────────────────────────────────────────────
echo "Step 7: Verifying..."

DEVICE=$(ls /dev/akida* 2>/dev/null | head -1)
if [ -n "$DEVICE" ]; then
    echo "  [OK] Device node created: $DEVICE"
else
    echo "  [FAIL] /dev/akida* not found after driver reload."
    echo "         Check: sudo dmesg | grep -i akida"
    echo "         A full power cycle (unplug power, wait 60s) may be required."
    exit 1
fi

# Quick MetaTF check if available
if command -v akida &>/dev/null; then
    AKIDA_OUT=$(akida devices 2>/dev/null || echo "")
    if echo "$AKIDA_OUT" | grep -qi "PCIe"; then
        echo "  [OK] MetaTF sees PCIe hardware: $AKIDA_OUT"
    else
        echo "  [INFO] 'akida devices' output: ${AKIDA_OUT:-empty}"
        echo "         Try: python3 tests/test_akida.py"
    fi
fi

echo ""
echo "========================================"
echo " PCIe ASPM fix applied successfully."
echo ""
echo " Test with:  python3 tests/test_akida.py"
echo ""
echo " NOTE: These fixes reset on every reboot."
echo " To make permanent, install the systemd service:"
echo "   sudo cp scripts/akida-pcie-fix.service /etc/systemd/system/"
echo "   sudo systemctl daemon-reload"
echo "   sudo systemctl enable akida-pcie-fix.service"
echo "========================================"
