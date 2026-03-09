# Brainchip AKD1000 M.2 on NVIDIA Jetson Orin NX

The Brainchip AKD1000 PCIe/M.2 module is compatible with the NVIDIA Jetson Orin NX, which features an exposed M.2 M-key PCIe slot on the carrier board.

This guide covers Jetson-specific installation requirements, TensorFlow setup for `aarch64`, and a complete troubleshooting log of every failure mode encountered during bring-up.

## 1. Physical Hardware Installation

1. Prepare your Jetson Orin NX. Make sure it is completely powered off and unplugged.
2. Locate the M.2 Key-M NVMe slot on the carrier board.

   > **Note:** If you have already installed an NVMe SSD in this slot, you must boot the Jetson from a USB stick instead to free up the slot for the Akida card.

3. Insert the AKD1000 M.2 card and screw it into the standoff.
4. Power on the system.

## 2. NVIDIA JetPack & System Requirements

- **Recommended JetPack version:** Latest stable JetPack 6.x (Ubuntu 22.04 aarch64)
- **Required Python version:** 3.10 to 3.12 (MetaTF 2.17+ does **not** support Python 3.9)
- **Install dependencies:**
  ```bash
  ./scripts/install_dependencies.sh
  ```

> **Tip:** Use a virtual environment with Conda:
> ```bash
> conda create --name akida_env python=3.11
> conda activate akida_env
> ```

## 3. TensorFlow / TF-Keras

> **Key insight:** The AKD1000 **is** the ML inference co-processor. All neural network execution happens in hardware on the Akida chip. The Jetson's CPU only runs Python pre/post-processing. **NVIDIA GPU-accelerated TensorFlow is not required.**

Standard `tf-keras` from PyPI works on Jetson's `aarch64` architecture:

```bash
pip install tf-keras==2.19
```

The `install_dependencies.sh` script in this repository handles this automatically.

## 4. Driver Installation

Install the PCIe driver using the provided script:

```bash
./scripts/install_drivers.sh
```

Because JetPack uses a custom L4T kernel, the script automatically detects Tegra architecture and installs `nvidia-l4t-kernel-headers` instead of standard `linux-headers`. After installation:

```bash
./scripts/check_hardware.sh
```

> **Important:** After every kernel update (`apt upgrade`), re-run `install_drivers.sh`. The official Brainchip driver does **not** use DKMS.

## 5. Installing MetaTF

With TF-Keras and the driver installed:

```bash
pip install akida==2.19.1
pip install cnn2snn==2.19.1
pip install akida-models==1.13.1
```

Then test hardware access:

```bash
python3 tests/test_akida.py
```

## 6. Power Settings (Optional)

For maximum performance:

```bash
sudo nvpmodel -m 0
```

---

## 7. Known Pitfalls & Troubleshooting

### Phase 3: Driver Installation — Wrong Kernel Headers

- **Symptom:** The `akida_pcie` module fails to compile.
- **Cause:** Standard `linux-headers` packages fail on Jetson because it uses a modified NVIDIA L4T kernel.
- **Fix:** Install `nvidia-l4t-kernel-headers` instead. The `install_drivers.sh` script in this repository handles this automatically by detecting the Tegra architecture.

### Phase 4: PCIe Timeout + Kernel Panic from Bootloader Edit

- **Symptom:** `Connection timed out` at `0xf0000010`, then an endless reboot loop after editing bootloader.
- **Cause:** `pcie_aspm=off` AND `iommu.passthrough=1` were both added to `/boot/extlinux/extlinux.conf`. On ARM64/Tegra, forcing IOMMU passthrough at boot level breaks DMA routing and causes a kernel panic.
- **Fix:** The 128GB external USB drive was mounted on another computer and the bad kernel arguments were manually deleted from the text file to restore boot.

### Phase 5: The PCIe Timeout — What NOT To Do

> ⚠️ **CRITICAL: Do NOT use `pcie_aspm=off` as a global kernel boot argument on Jetson Orin.**

Adding `pcie_aspm=off` to `/boot/extlinux/extlinux.conf` **bricked the Jetson twice** and required full OS reflashes. The Jetson's NVMe SSD shares the same PCIe root complex — disabling ASPM globally severs the kernel's connection to it at boot.

**Safe approaches:**

1. **Driver reload (try this first):**
   ```bash
   sudo ./scripts/fix_jetson_pcie.sh
   ```

2. **Targeted ASPM disable (advanced):** Disable ASPM only on the Akida device's specific slot using `setpci` — never globally. Find the BDF:
   ```bash
   lspci -D | grep -iE "Brainchip|Akida|Co-processor"
   ```
   Then disable ASPM only on that device (replace `<BDF>` with the address found above):
   ```bash
   sudo setpci -s <BDF> CAP_EXP+10.w=0000
   ```

3. **Reseat the hardware:** Power off, remove the AKD1000, reinsert firmly.

The `apply_boot_fix.sh` script has been removed from this repository and must not be recreated.

### Phase 6: BAR0 MMIO Returns 0xFFFFFFFF — Internal Bus Non-Responsive

This is the most subtle failure mode. The driver reports successful probe and `/dev/akida0` is created, but **all DMA operations time out** and MetaTF returns `Connection timed out` or `No devices detected`.

**Root cause (discovered through deep PCIe diagnostics):**

The AKD1000 uses a DW PCIe IP (DesignWare) split into two layers:
- **PCIe MAC layer** — handles link training, config space TLPs. Stays functional.
- **Application layer** — the Akida neural processor core, DBI AXI slave, eDMA engine. Can be dead while the MAC layer runs fine.

When the application layer is non-functional:
- `lspci` enumerates the device ✅
- Config space reads (iATU registers) return correct values ✅
- **ALL BAR MMIO reads return `0xFFFFFFFF`** ❌
- DMA operations time out after 2 seconds ❌

The driver probe "succeeds" because `0xFFFFFFFF` masked to `GENMASK(3,0)` gives 15, which is then clamped to the configured 2 channels — a valid-looking result. No register write failures are reported because PCIe Memory Write TLPs are posted (fire-and-forget, no ACK).

**Verified diagnostics on Jetson Orin NX:**

```
Endpoint BDF:     0004:01:00.0
Root port:        0004:00:00.0  (tegra194-pcie 14160000.pcie)
PCIe link:        Gen2 x2  ✅
Config space:     Working (iATU Region 0→0xFCC00000, 1→0xF8C00000, 2→0x20000000) ✅
BAR0 MMIO:        0xFFFFFFFF  ❌
BAR2 MMIO:        0xFFFFFFFF  ❌
DMA pread:        errno 110 (Connection timed out)  ❌
```

**Diagnostic script:** Run the following to generate a full diagnostic report:
```bash
sudo ./scripts/diagnose_pcie.sh
```

**Quick diagnostic:** Test BAR0 MMIO directly:
```bash
python3 -c "
import mmap, os, struct, signal, sys
signal.signal(signal.SIGALRM, lambda s,f: (print('[FAIL] Timeout'), sys.exit(1)))
signal.alarm(5)
fd = os.open('/dev/akida0', os.O_RDWR)
m = mmap.mmap(fd, 4096, mmap.MAP_SHARED, mmap.PROT_READ, offset=0)
val = struct.unpack('<I', m[:4])[0]
print(f'BAR0[0x00] = 0x{val:08x}')
print('[OK] Internal bus responding.' if val != 0xFFFFFFFF else '[FAIL] Internal bus dead.')
m.close(); os.close(fd)
signal.alarm(0)
"
```

**Try the Jetson fix script first:**
```bash
sudo ./scripts/fix_jetson_pcie.sh
```

If the fix script reports BAR0 still returns `0xFFFFFFFF`, proceed to the x86 cross-test below.

### Phase 7: x86 Cross-Test — Determining if the Card is Faulty

Testing the AKD1000 in a standard x86 PC definitively determines whether the issue is the card or the Jetson slot.

**Requirements:** Any x86-64 PC with an M.2 Key-M slot. Ubuntu/Debian preferred.

**Steps on the x86 machine:**

1. Install build tools and the driver:
   ```bash
   sudo apt install -y build-essential linux-headers-$(uname -r) git
   cd ~/akida_dw_edma  # or git clone https://github.com/Brainchip-Inc/akida_dw_edma
   chmod +x install.sh && sudo ./install.sh
   ```

2. Verify the card enumerated:
   ```bash
   lspci | grep Co-processor
   # Expected: Co-processor: Brainchip Inc AKD1000 Neural Network Coprocessor [Akida] (rev 01)
   ```

3. Run hardware check:
   ```bash
   ./scripts/check_hardware.sh
   ```

4. Test BAR0 MMIO (the critical test):
   ```bash
   python3 -c "
   import mmap, os, struct, signal, sys
   signal.signal(signal.SIGALRM, lambda s,f: (print('[FAIL] Timeout'), sys.exit(1)))
   signal.alarm(5)
   fd = os.open('/dev/akida0', os.O_RDWR)
   m = mmap.mmap(fd, 4096, mmap.MAP_SHARED, mmap.PROT_READ, offset=0)
   val = struct.unpack('<I', m[:4])[0]
   print(f'BAR0[0x00] = 0x{val:08x}')
   result = 'OK - card works' if val != 0xFFFFFFFF else 'FAIL - card internal bus dead'
   print(result)
   m.close(); os.close(fd)
   signal.alarm(0)
   "
   ```

5. Full MetaTF test:
   ```bash
   python3 -m venv ~/akida_env && source ~/akida_env/bin/activate
   pip install akida==2.19.1 cnn2snn==2.19.1 tf-keras==2.19 akida-models==1.13.1
   python3 tests/test_akida.py
   ```

**Interpreting results:**

| BAR0 on x86 | BAR0 on Jetson | Conclusion |
|---|---|---|
| Valid value | `0xFFFFFFFF` | Jetson slot power/device tree issue. Card is fine. |
| `0xFFFFFFFF` | `0xFFFFFFFF` | AKD1000 card hardware fault. Contact Brainchip for RMA. |
| Valid value | Valid value | Both work — original Jetson issue resolved. |

---

## 8. Key Takeaways: What Not to Do

1. **Do not trust standard host OS settings for flashing**: Always expand `usbfs_memory_mb` and kill autosuspend before flashing a Jetson.
2. **Do not rush a hardware reset**: If a low-level process fails, unplug power and wait 60 seconds before rebooting.
3. **Do not treat Tegra Linux like Desktop Linux**: Standard Ubuntu tutorials for GRUB, kernel parameters, or headers will fail on L4T. Always use Jetson-specific documentation.
4. **Do not modify the bootloader without a physical backdoor**: Never edit `extlinux.conf` without a serial debug console or an external-USB OS install that you can mount on another machine to undo mistakes.
5. **Do not do a PCIe bus rescan on Jetson**: Always use `scripts/resetpcie.sh` (driver unload/reload only). Bus remove + rescan forces Tegra's ASPM to wipe BAR memory mappings, causing `BAR I/O remapping failed (-22)`.
