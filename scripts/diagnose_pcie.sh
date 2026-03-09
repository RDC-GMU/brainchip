#!/bin/bash
# ============================================================================
#  Brainchip AKD1000 — PCIe Diagnostic Script
#
#  Collects comprehensive information about the PCIe link, BAR assignments,
#  driver status, and tests both MMIO (mmap) and DMA (pread) paths.
# ============================================================================

echo "========================================"
echo " Brainchip AKD1000 PCIe Diagnostics"
echo "========================================"
echo ""

# ── 1. Device enumeration ─────────────────────────────────────────
echo "=== 1. PCIe Device Enumeration ==="
lspci -D | grep -iE "Co-processor|Brainchip|Akida" || echo "  No Akida device found"
echo ""

# ── 2. Full device details ────────────────────────────────────────
PCI_ID=$(lspci -D | grep -iE "Co-processor|Brainchip|Akida" | awk '{print $1}' | head -1)
if [ -z "$PCI_ID" ]; then
    echo "ERROR: No Akida device found on PCIe bus. Exiting."
    exit 1
fi

echo "=== 2. Full PCIe Device Details (endpoint: $PCI_ID) ==="
sudo lspci -vvv -s "$PCI_ID" 2>/dev/null
echo ""

# ── 3. Root port details ──────────────────────────────────────────
DOMAIN=$(echo "$PCI_ID" | cut -d: -f1)
ROOT_PORT="${DOMAIN}:00:00.0"
echo "=== 3. Root Port Details ($ROOT_PORT) ==="
sudo lspci -vvv -s "$ROOT_PORT" 2>/dev/null || echo "  Root port not found at $ROOT_PORT"
echo ""

# ── 4. PCIe topology ─────────────────────────────────────────────
echo "=== 4. PCIe Topology (domain $DOMAIN) ==="
lspci -D -PP | grep "^$DOMAIN" || true
echo ""

# ── 5. Kernel driver status ───────────────────────────────────────
echo "=== 5. Kernel Module Status ==="
lsmod | grep -E "akida|edma|virt_dma" || echo "  No akida modules loaded"
echo ""

echo "=== 5b. Device node ==="
ls -la /dev/akida* 2>/dev/null || echo "  No /dev/akida* found"
echo ""

# ── 6. Kernel messages ────────────────────────────────────────────
echo "=== 6. Kernel Messages (akida/pcie related) ==="
sudo dmesg | grep -iE "akida|edma|brainchip|0004:01" | tail -40
echo ""

# ── 7. PCIe link status via setpci ────────────────────────────────
echo "=== 7. PCIe Register Dump ==="
echo "--- Endpoint ($PCI_ID) ---"
echo -n "  Link Control (CAP_EXP+10):  "
sudo setpci -s "$PCI_ID" CAP_EXP+10.w 2>/dev/null || echo "N/A"
echo -n "  Link Status  (CAP_EXP+12):  "
sudo setpci -s "$PCI_ID" CAP_EXP+12.w 2>/dev/null || echo "N/A"
echo -n "  Device Control (CAP_EXP+8): "
sudo setpci -s "$PCI_ID" CAP_EXP+8.w 2>/dev/null || echo "N/A"
echo -n "  Command Register:           "
sudo setpci -s "$PCI_ID" COMMAND.w 2>/dev/null || echo "N/A"
echo ""

echo "--- Root Port ($ROOT_PORT) ---"
echo -n "  Link Control (CAP_EXP+10):  "
sudo setpci -s "$ROOT_PORT" CAP_EXP+10.w 2>/dev/null || echo "N/A"
echo -n "  Link Status  (CAP_EXP+12):  "
sudo setpci -s "$ROOT_PORT" CAP_EXP+12.w 2>/dev/null || echo "N/A"
echo ""

# ── 8. BAR assignments ───────────────────────────────────────────
echo "=== 8. BAR Assignments ==="
sudo lspci -s "$PCI_ID" -vv 2>/dev/null | grep -E "Region|Memory at"
echo ""

# ── 9. IOMMU / SMMU status ───────────────────────────────────────
echo "=== 9. IOMMU / SMMU Status ==="
if [ -d /sys/class/iommu ]; then
    ls /sys/class/iommu/ 2>/dev/null || echo "  No IOMMU devices"
fi
sudo dmesg | grep -iE "iommu|smmu" | grep -i "$PCI_ID" | tail -5 || echo "  No IOMMU messages for this device"
echo ""

# ── 10. Runtime PM status ────────────────────────────────────────
echo "=== 10. Runtime PM Status ==="
SYSFS_EP="/sys/bus/pci/devices/$PCI_ID"
if [ -d "$SYSFS_EP" ]; then
    echo -n "  power/control:       "; cat "$SYSFS_EP/power/control" 2>/dev/null
    echo -n "  power/runtime_status: "; cat "$SYSFS_EP/power/runtime_status" 2>/dev/null
fi
echo ""

# ── 11. Test: Direct mmap read from BAR0 ─────────────────────────
echo "=== 11. Direct MMIO Test (mmap BAR0, bypasses DMA) ==="
if [ -e /dev/akida0 ]; then
    # Build mmap_access if not built
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    REPO_ROOT="$(dirname "$SCRIPT_DIR")"
    TEST_DIR="$REPO_ROOT/akida_dw_edma/test"

    if [ -d "$TEST_DIR" ]; then
        if [ ! -f "$TEST_DIR/mmap_access" ]; then
            echo "  Building mmap_access test tool..."
            make -C "$TEST_DIR" mmap_access 2>/dev/null
        fi

        if [ -f "$TEST_DIR/mmap_access" ]; then
            echo "  Reading offset 0x0 (32-bit) via mmap..."
            timeout 5 "$TEST_DIR/mmap_access" /dev/akida0 0x0 32 2>&1 && echo "  [OK] MMIO read succeeded" || echo "  [FAIL] MMIO read failed or timed out"
            echo ""
            echo "  Reading offset 0x50 (32-bit) via mmap (Akida ID register)..."
            timeout 5 "$TEST_DIR/mmap_access" /dev/akida0 0x50 32 2>&1 && echo "  [OK] MMIO read succeeded" || echo "  [FAIL] MMIO read failed or timed out"
        else
            echo "  [SKIP] Could not build mmap_access."
        fi
    else
        echo "  [SKIP] test directory not found at $TEST_DIR"
    fi
else
    echo "  [SKIP] /dev/akida0 does not exist"
fi
echo ""

# ── 12. Test: DMA pread (same as MetaTF uses) ────────────────────
echo "=== 12. DMA pread Test (same path MetaTF uses) ==="
if [ -e /dev/akida0 ]; then
    # Quick python pread test
    python3 -c "
import os, errno
fd = os.open('/dev/akida0', os.O_RDONLY)
try:
    # Test 1: Read from Brainchip's own test address 0xfcc00050
    try:
        data = os.pread(fd, 4, 0xfcc00050)
        print(f'  pread @0xfcc00050: {data.hex()} [OK]')
    except OSError as e:
        print(f'  pread @0xfcc00050: errno {e.errno} - {e.strerror} [FAIL]')

    # Test 2: Read from MetaTF's address 0xf0000010
    try:
        data = os.pread(fd, 4, 0xf0000010)
        print(f'  pread @0xf0000010: {data.hex()} [OK]')
    except OSError as e:
        print(f'  pread @0xf0000010: errno {e.errno} - {e.strerror} [FAIL]')
finally:
    os.close(fd)
" 2>&1
else
    echo "  [SKIP] /dev/akida0 does not exist"
fi
echo ""

echo "========================================"
echo " Diagnostics complete."
echo " Please share this full output."
echo "========================================"
