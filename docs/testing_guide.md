# Testing Your Brainchip AKD1000 M.2 Setup

After physically installing the hardware and running the setup scripts, use the following steps to verify the driver and MetaTF stack are working correctly.

## 1. Validate Driver & PCIe Connection (`check_hardware.sh`)

Run the hardware check script, which performs four checks in sequence:

```bash
./scripts/check_hardware.sh
```

**What this checks:**

| # | Check | Tool | Expected Result |
|---|---|---|---|
| 1 | PCIe bus | `lspci` | `Co-processor: Device 1e7c:bca1 (rev 01)` |
| 2 | Kernel module loaded | `lsmod` | `akida` module present |
| 3 | Device node exists | `/dev/akida*` | `/dev/akida0` visible |
| 4 | MetaTF hardware enumeration | `akida devices` | `PCIe/NSoC_v2` listed |

Check 4 (`akida devices`) is the canonical confirmation from the official Brainchip install guide — if it shows a `PCIe/` entry, your full stack is working end-to-end.

## 2. Validate MetaTF Python Stack (`test_akida.py`)

Once the hardware check passes, run the Python test to confirm the `akida` library can bind to the hardware device (not software simulation):

```bash
python tests/test_akida.py
```

**What this checks:**
- `akida` imports correctly (no missing dependency errors)
- `akida.devices()` returns a hardware device — **not** software emulation

---

## Troubleshooting

### `lspci` gives no results (Check 1 fails)

The Akida card is not visible on the PCIe bus.

1. **Power the machine fully off** (not just restart).
2. Reseat the AKD1000 M.2 card firmly into its slot — it is a one-lane card but fits into 2-, 4-, or 8-lane slots. Ensure the back edge of the card extends past the PCIe connector.
3. Power back on and re-run `./scripts/check_hardware.sh`.

### `akida-pcie` kernel module not loaded (Check 2 fails)

```bash
sudo modprobe akida-pcie
```

If that fails, the driver was not installed correctly. Re-run the installer:

```bash
./scripts/install_drivers.sh
```

### `/dev/akida*` not found (Check 3 fails)

The driver loaded but did not attach to the hardware cleanly. Run the PCIe reset utility:

```bash
./scripts/resetpcie.sh
```

### `akida devices` shows no PCIe device (Check 4 fails)

Two possible causes:

- **MetaTF version too old:** You must have MetaTF `>= 2.2.0`. The current recommended version is `2.19.1`. Upgrade:
  ```bash
  pip3 install akida==2.19.1
  ```
- **Permissions issue:** The `/dev/akida0` node may not be accessible to your user. The official `install.sh` sets udev rules automatically, but confirm by testing with sudo:
  ```bash
  sudo akida devices
  ```
  If this works but the non-sudo version doesn't, your user needs to be added to the appropriate group or the udev rules need to be reloaded:
  ```bash
  sudo udevadm control --reload-rules && sudo udevadm trigger
  ```

### `RuntimeError: unexpected transfer len: 1 expected: 4`

This is a known transient PCIe communication error. Run the reset utility in a separate terminal and retry:

```bash
./scripts/resetpcie.sh
```

### System stuck / applications not responding

Reboot the system fully. If a low-level PCIe operation fails, an immediate restart may carry ghost errors into the next session — always unplug power and wait ~60 seconds before rebooting.
