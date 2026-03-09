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

---

## Troubleshooting

### `lspci` gives no results (Check 1 fails)

The Akida card is not visible on the PCIe bus.

1. **Power the machine fully off** (not just restart).
2. Reseat the AKD1000 M.2 card firmly into its slot.
3. Power back on. Re-run `./scripts/check_hardware.sh`.

### `akida_pcie` kernel module not loaded (Check 2 fails)

```bash
sudo modprobe akida_pcie
```

If that fails, reinstall the driver:

```bash
./scripts/install_drivers.sh
```

> **Jetson note:** After any kernel update (`apt upgrade`), you must re-run `install_drivers.sh`. The driver does not use DKMS.

### `/dev/akida*` not found (Check 3 fails)

The driver loaded but did not attach cleanly. Use the safe reset utility:

```bash
./scripts/resetpcie.sh
```

> **Jetson warning:** Do NOT add `pcie_aspm=off` to `/boot/extlinux/extlinux.conf`. This bricks the Jetson — see [jetson_orin_nano.md](jetson_orin_nano.md) Phase 5.

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

This is the most critical failure mode. The card's **internal application core is not responding**, even though the PCIe link and driver probe both succeed. The driver probe falsely succeeds because `0xFFFFFFFF` masks to a valid-looking channel count.

**Symptom:** `check_hardware.sh` passes checks 1–4, but MetaTF gives `Connection timed out` or `No devices detected`.

**Deep diagnostics:**
```bash
sudo ./scripts/diagnose_pcie.sh
```

**On Jetson Orin NX** — try the runtime PM fix first:
```bash
sudo ./scripts/fix_jetson_pcie.sh
```

**Cross-platform hardware test:** If the fix script doesn't help, test the card in an x86 PC:
1. Install on x86 machine with `sudo ./install.sh` from `akida_dw_edma/`
2. Run `./scripts/check_hardware.sh`
3. If BAR0 still returns `0xFFFFFFFF` → card is hardware-faulty (RMA)
4. If card works on x86 → issue is Jetson M.2 slot power or device tree configuration

See [jetson_orin_nano.md](jetson_orin_nano.md) Phase 6 for the complete root cause analysis.

### `RuntimeError: unexpected transfer len: 1 expected: 4`

Transient PCIe communication error. Run the reset utility:

```bash
./scripts/resetpcie.sh
```

> **Jetson:** Use `resetpcie.sh` only (driver unload/reload). Do NOT do a bus rescan — it corrupts BAR mappings on the Tegra PCIe controller.

### System stuck / applications not responding

Reboot fully. If a low-level PCIe operation fails, ghost errors can persist. Always **unplug power and wait ~60 seconds** before rebooting.
