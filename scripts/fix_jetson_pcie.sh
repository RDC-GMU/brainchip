#!/bin/bash
# ============================================================================
#  Brainchip AKD1000 — Jetson Orin PCIe Reset & Power Fix
#
#  Context: On Jetson Orin NX (Tegra194, pcie@14160000), after akida_pcie
#  loads, the AKD1000 can become unresponsive with all BAR MMIO reads
#  returning 0xFFFFFFFF. This is caused by runtime PM suspending the device
#  after probe completes.
#
#  This script performs a safe driver-only reload (NO PCIe bus rescan —
#  which corrupts BAR mappings on Tegra) and forces the device to stay
#  powered via the sysfs runtime PM interface.
#
#  Steps:
#    1. Unload the akida_pcie driver
#    2. Disable ASPM on AKD1000 endpoint and its root port
#    3. Disable L1 sub-states on both if supported
#    4. Force runtime PM to "always on" on both
#    5. Reload the driver
#    6. Verify /dev/akida0 was created
#    7. BAR0 MMIO sanity check (0xFFFFFFFF = hardware-level issue)
#
#  Usage:
#    sudo ./scripts/fix_jetson_pcie.sh
#
#  Permanent (auto-runs at boot):
#    sudo cp scripts/akida-pcie-fix.service /etc/systemd/system/
#    sudo systemctl daemon-reload
#    sudo systemctl enable akida-pcie-fix.service
#
#  NOTE: If BAR0 still returns 0xFFFFFFFF after this script, the card's
#  internal application core is hardware-faulted. See docs/jetson_orin_nano.md
#  Phase 6 and the x86 cross-test procedure.
# ============================================================================

set -euo pipefail

echo "========================================"
echo " Brainchip AKD1000 Jetson PCIe Fix"
echo "========================================"
echo ""

# ── Must run as root ──────────────────────────────────────────────
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root (sudo)."
    exit 1
fi

# ── Step 0: Find the Akida endpoint and its root port ─────────────
echo "Step 0: Locating Akida device and root port..."

PCI_ID=$(lspci -D | grep -iE "Co-processor.*Brainchip|Brainchip.*Co-processor|AKD1000|Akida" \
    | awk '{print $1}' | head -1)

if [ -z "$PCI_ID" ]; then
    echo "  [FAIL] No Brainchip Akida device found on the PCIe bus."
    echo "         Ensure the M.2 card is firmly seated. Try a full power cycle."
    exit 1
fi

echo "  Akida endpoint: $PCI_ID"

# Correctly extract only the domain portion.
# PCI_ID format: "DOMAIN:BUS:DEV.FN" e.g. "0004:01:00.0"
# Root port is always DOMAIN:00:00.0
DOMAIN=$(echo "$PCI_ID" | cut -d: -f1)
ROOT_PORT="${DOMAIN}:00:00.0"

if ! lspci -s "$ROOT_PORT" &>/dev/null; then
    echo "  [WARN] Could not find root port at $ROOT_PORT, will skip root port steps."
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
echo "Step 4: Disabling L1 sub-states..."

disable_l1ss() {
    local DEV="$1"
    local LABEL="$2"
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
[ -n "$ROOT_PORT" ] && disable_l1ss "$ROOT_PORT" "Root port"
echo ""

# ── Step 5: Force runtime PM to "on" ─────────────────────────────
echo "Step 5: Forcing runtime PM to 'always on'..."
SYSFS_EP="/sys/bus/pci/devices/$PCI_ID/power/control"
[ -f "$SYSFS_EP" ] && echo "on" > "$SYSFS_EP" && echo "  Endpoint:  runtime PM = on"
if [ -n "$ROOT_PORT" ]; then
    SYSFS_RP="/sys/bus/pci/devices/$ROOT_PORT/power/control"
    [ -f "$SYSFS_RP" ] && echo "on" > "$SYSFS_RP" && echo "  Root port: runtime PM = on"
fi
echo ""

# ── Step 6: Reload the driver ─────────────────────────────────────
echo "Step 6: Loading akida_pcie driver..."
modprobe akida_pcie
sleep 2
echo "  Done."
echo ""

# ── Step 7: Verify device node ────────────────────────────────────
echo "Step 7: Verifying device node..."
DEVICE=$(ls /dev/akida* 2>/dev/null | head -1)
if [ -n "$DEVICE" ]; then
    echo "  [OK] Device node created: $DEVICE"
else
    echo "  [FAIL] /dev/akida* not found after driver reload."
    echo "         Check: sudo dmesg | grep -i akida"
    echo "         A full power cycle (unplug, wait 60s) may be required."
    exit 1
fi
echo ""

# ── Step 8: BAR0 MMIO sanity check ────────────────────────────────
# 0xFFFFFFFF = AKD1000 internal bus not responding (hardware issue).
# Any other value = internal bus is alive, DMA issue may be transient.
echo "Step 8: BAR0 MMIO sanity check..."
python3 - <<'PYEOF'
import mmap, os, struct, signal, sys

def timeout(s, f):
    print("  [WARN] MMIO read timed out — card may be in deep sleep")
    sys.exit(0)

signal.signal(signal.SIGALRM, timeout)
signal.alarm(5)

import glob
devs = glob.glob('/dev/akida*')
if not devs:
    print("  [SKIP] No /dev/akida* found")
    sys.exit(0)

fd = os.open(devs[0], os.O_RDWR)
m = mmap.mmap(fd, 4096, mmap.MAP_SHARED, mmap.PROT_READ, offset=0)
val = struct.unpack('<I', m[:4])[0]
m.close()
os.close(fd)
signal.alarm(0)

if val == 0xFFFFFFFF:
    print("  [WARN] BAR0 = 0xffffffff — card internal bus NOT responding.")
    print("         This is a hardware-level issue this script cannot fix.")
    print("         See docs/jetson_orin_nano.md Phase 6 and the x86 test.")
else:
    print(f"  [OK]  BAR0[0x00] = 0x{val:08x} — internal bus responding.")
PYEOF

# ── MetaTF check if available ─────────────────────────────────────
if command -v akida &>/dev/null; then
    AKIDA_OUT=$(akida devices 2>/dev/null || echo "")
    if echo "$AKIDA_OUT" | grep -qi "PCIe"; then
        echo "  [OK] MetaTF sees PCIe hardware: $AKIDA_OUT"
    else
        echo "  [INFO] akida devices: ${AKIDA_OUT:-empty}"
        echo "         Try: python3 tests/test_akida.py"
    fi
fi

echo ""
echo "========================================"
echo " PCIe fix applied."
echo " Test: python3 tests/test_akida.py"
echo ""
echo " For persistent fix across reboots:"
echo "   sudo cp scripts/akida-pcie-fix.service /etc/systemd/system/"
echo "   sudo systemctl daemon-reload && sudo systemctl enable akida-pcie-fix.service"
echo ""
echo " If BAR0 returned 0xffffffff, this is a hardware issue."
echo " See: docs/jetson_orin_nano.md — Phase 6 & x86 cross-test"
echo "========================================"
