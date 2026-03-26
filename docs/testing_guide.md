# Testing Your Brainchip AKD1000 M.2 Setup

## 1. Validate Driver & PCIe Connection (`check_hardware.sh`)

```bash
./scripts/check_hardware.sh
```

**What this checks:**

| # | Check | Tool | Expected Result |
|---|---|---|---|
| 1 | PCIe bus | `lspci` | `Co-processor: Device 1e7c:bca1 (rev 01)` |
| 2 | Kernel module loaded | `lsmod` | `akida_pcie` module present |
| 3 | Device node exists | `/dev/akida*` | `/dev/akida0` visible |
| 4 | MetaTF hardware enumeration | `akida devices` | `PCIe/NSoC_v2` listed |
| 5 | BAR0 MMIO integrity | `mmap` read | Value ≠ `0xFFFFFFFF` |

Check 4 (`akida devices`) is the official Brainchip confirmation. Check 5 (BAR0 MMIO) is the deeper hardware integrity test — if BAR0 returns all-FFs, the card's internal bus is non-functional regardless of whether the driver loaded cleanly.

## 2. Validate MetaTF Python Stack (`test_akida.py`)

```bash
python3 tests/test_akida.py
```

**What this checks:**
- `akida` imports correctly
- `akida.devices()` returns a **hardware** device, not software emulation

## 3. Run Object Detection (`test_object_detection.py`)

```bash
python3 tests/test_object_detection.py
```

Loads the pre-trained YOLOv2 model (PASCAL-VOC, 20 classes), converts it to Akida format, runs inference, and saves an annotated output image.

```bash
# With a custom image
python3 tests/test_object_detection.py --image photo.jpg

# FPS benchmark
python3 tests/test_object_detection.py --benchmark 100
```

---

## Troubleshooting

### `lspci` gives no results (Check 1 fails)

The Akida card is not visible on the PCIe bus.

1. **Power the machine fully off** (not just restart).
2. Reseat the AKD1000 M.2 card firmly into its slot via the M.2 HAT+.
3. Power back on. Re-run `./scripts/check_hardware.sh`.

### `akida_pcie` kernel module not loaded (Check 2 fails)

```bash
sudo modprobe akida_pcie
```

If that fails, reinstall the driver:

```bash
./scripts/install_drivers.sh
```

> **Note:** After any kernel update (`apt upgrade`), you must re-run `install_drivers.sh`. The driver must be rebuilt for each new kernel version.

### `/dev/akida*` not found (Check 3 fails)

The driver loaded but did not attach cleanly. Use the safe reset utility:

```bash
./scripts/resetpcie.sh
```

### `akida devices` shows no PCIe device (Check 4 fails)

Two possible causes:

- **MetaTF version too old** (must be ≥ 2.2.0, recommended 2.19.1):
  ```bash
  pip install akida==2.19.1
  ```
- **Permissions issue** — `/dev/akida0` not accessible to your user. Test with sudo:
  ```bash
  sudo akida devices
  ```
  If root works but your user doesn't, reload udev rules:
  ```bash
  sudo udevadm control --reload-rules && sudo udevadm trigger
  ```

### BAR0 MMIO returns `0xFFFFFFFF` (Check 5 fails)

The card's **internal application core is not responding**, even though the PCIe link and driver probe both succeed.

**Symptom:** `check_hardware.sh` passes checks 1–4, but MetaTF gives `Connection timed out` or `No devices detected`.

**Deep diagnostics:**
```bash
sudo ./scripts/diagnose_pcie.sh
```

If diagnostics confirm the card is non-responsive, test it in an x86 PC with a standard M.2 slot to determine if the card itself is faulty (RMA) or if the issue is Pi-specific (HAT+ slot power or device tree).

### `RuntimeError: unexpected transfer len: 1 expected: 4`

Transient PCIe communication error. Run the reset utility:

```bash
./scripts/resetpcie.sh
```

### System stuck / applications not responding

Reboot fully. If a low-level PCIe operation fails, ghost errors can persist. Always **unplug power and wait ~60 seconds** before rebooting.
