# Brainchip AKD1000 M.2 on NVIDIA Jetson Orin Nano

The Brainchip AKD1000 PCIe/M.2 module is highly compatible with the NVIDIA Jetson Orin Nano since the Jetson utilizes an `aarch64` processor architecture and features an exposed M.2 M-key PCIe slot underneath the carrier board.

This guide covers the specific requirements and steps for installing and running MetaTF on a Jetson Orin Nano.

## 1. Physical Hardware Installation

1. Prepare your Jetson Orin Nano Developer Kit. Make sure it is completely powered off and unplugged.
2. Locate the M.2 Key-M NVMe slot underneath the carrier board. Note: If you have already flashed the Jetson OS to an NVMe SSD installed in this slot, you must boot from a USB Stick instead to free up the PCIe slot for the Akida coprocessor.
3. Insert the Brainchip AKD1000 M.2 into the M.2 Key-M slot and screw it securely into the standoff. 
4. Insert your flashed USB Stick (containing JetPack) and power on the system.

## 2. NVIDIA JetPack & System Requirements

Brainchip's software requires an `aarch64` Linux distribution. On the Orin Nano, this means utilizing NVIDIA JetPack.

- **Recommended JetPack version:** Latest stable JetPack (6.x series) running Ubuntu 22.04.
- **Required Python version:** 3.10 to 3.12 (MetaTF 2.17+ does **not** support Python 3.9).
- **Install Dependencies:** Set up the foundational compilers, Jetson-specific libraries, and Python environment by running:
  ```bash
  ./scripts/install_dependencies.sh
  ```

> **Tip:** It is strongly recommended to use a virtual environment. With Conda:
> ```bash
> conda create --name akida_env python=3.11
> conda activate akida_env
> ```

## 3. TensorFlow / TF-Keras on Jetson (Crucial Step)

MetaTF 2.17+ requires **TF-Keras 2.19** (bundled with TensorFlow 2.19). Because the Jetson uses an ARM-based Tegra GPU, you **cannot** simply run `pip install tensorflow` and get a GPU-accelerated build.

> **Note:** MetaTF 2.16 was the last release supporting TensorFlow 2.15 / Keras 2 / Python 3.9. If you are starting fresh, install MetaTF 2.17+.

Install TF-Keras for `aarch64` before installing MetaTF:
```bash
pip3 install tf-keras==2.19
```

For full GPU acceleration via CUDA on Jetson, also install NVIDIA's compatible TensorFlow build. Check the [NVIDIA JetPack TensorFlow index](https://developer.download.nvidia.com/compute/redist/jp/) for the wheel matching your JetPack version:
```bash
# Example for JetPack 6.x — verify the exact URL against your JetPack version:
pip3 install --extra-index-url https://developer.download.nvidia.com/compute/redist/jp/v61 tensorflow
```
*(Check the [NVIDIA Developer Forums](https://forums.developer.nvidia.com/) for the exact index URL matching your specific JetPack version.)*

## 4. Driver Installation

Once your software environment is prepped, install the PCIe driver using the provided auto-installer script in this repository.

Because JetPack utilizes custom L4T kernel headers, ensure they are present before proceeding:

1. Run the Brainchip installer script:
    ```bash
    ./scripts/install_drivers.sh
    ```
2. Run the hardware check to verify the Jetson PCIe bus recognizes the AKD1000:
    ```bash
    ./scripts/check_hardware.sh
    ```

## 5. Installing MetaTF

With TF-Keras installed and the Brainchip PCIe drivers loaded, install the MetaTF packages. Install components **individually** (not via `pip install -r requirements.txt`) to avoid pip overwriting your Jetson-specific TensorFlow build:

```bash
pip3 install akida==2.19.1
pip3 install cnn2snn==2.19.1
pip3 install akida-models==1.13.1
```

> **Version note:** These are the latest stable versions as of the MetaTF 2.19 release. Check [doc.brainchipinc.com](https://doc.brainchipinc.com/) for the most current pinned versions.

Finally, execute the test script to confirm hardware execution:
```bash
python3 tests/test_akida.py
```

## Power Settings (Optional)

For maximum performance, put your Jetson Orin Nano into "MAXN" mode using `nvpmodel`:
```bash
sudo nvpmodel -m 0
```

## 6. Known Pitfalls & Troubleshooting 

### Phase 3: The BrainChip Driver Installation
- **What Happened**: With the OS installed, the BrainChip `akida` Python library failed to detect the physical M.2 Co-processor, defaulting to software emulation.
- **What Went Wrong**: Installing the Python software library via `pip` is not enough, the underlying Linux kernel module (`akida_pcie`) to bridge the physical hardware was missing. When attempting to compile it, the standard Ubuntu `linux-headers` package failed because the Jetson uses a heavily modified NVIDIA kernel.
- **The Fix**: Install the specific `nvidia-l4t-kernel-headers` package instead. The `install_drivers.sh` script provided in this repository now automatically detects the Tegra architecture and installs these correct headers to successfully compile the driver from source and generate the `/dev/akida0` hardware node.

### Phase 4: The PCIe Timeout and Kernel Panic
- **What Happened**: The Python script successfully reached the hardware driver, but threw a `Connection timed out` error at memory address `0xf0000010`. In an attempt to fix this hardware timeout, editing the Jetson's bootloader caused the Jetson to instantly go into an endless reboot loop.
- **What Went Wrong**: It was correctly assumed that standard Linux PCIe power management (ASPM) was putting the Co-processor to sleep causing the timeouts. However, the bootloader was modified by adding *both* `pcie_aspm=off` AND `iommu.passthrough=1` to the `/boot/extlinux/extlinux.conf` file. The Orin Nano's ARM64 architecture is fiercely strict on memory, so forcing IOMMU passthrough at the bootloader level on a Tegra kernel completely broke DMA routing and caused a catastrophic kernel panic during boot.
- **The Fix**: The 128GB external USB drive was pulled, mounted directly on another computer, and the bad kernel arguments were manually deleted from the text file to restore the boot sequence.

### Phase 5: The PCIe Timeout — What NOT to Do

> ⚠️ **CRITICAL: Do NOT use `pcie_aspm=off` as a global kernel boot argument on Jetson Orin Nano.**

The `error reading at 0xf0000010 len: 4 errno(110): Connection timed out` error was observed when the Brainchip AKD1000 card enters a deep PCIe ASPM sleep state.

Attempts were made to fix this by appending `pcie_aspm=off` to `/boot/extlinux/extlinux.conf`. **This bricked the Jetson twice and required two full OS reflashes.** The Jetson Orin Nano's NVMe SSD shares the same PCIe root complex as the M.2 slot — disabling ASPM globally severs the kernel's connection to the NVMe drive at boot, causing an unrecoverable `partition id not found` failure.

**Safe approaches to the timeout issue:**

1. **Warm reset (try this first):** The `resetpcie.sh` script performs a driver unload → PCIe bus remove → rescan → driver reload without any reboot or bootloader changes:
   ```bash
   ./scripts/resetpcie.sh
   ```

2. **Targeted ASPM disable (advanced):** If the timeout persists, disable ASPM *only* on the Akida device's specific PCIe slot — not the whole bus — using `setpci`. First, find the device's BDF address:
   ```bash
   lspci -D | grep -iE "Brainchip|Akida|Co-processor"
   ```
   Then disable ASPM only on that device (replace `<BDF>` with the address found above):
   ```bash
   sudo setpci -s <BDF> CAP_EXP+10.w=0000
   ```

3. **Reseat the hardware:** A loose M.2 card can cause intermittent timeout errors. Power off, reseat the AKD1000, and re-run `./scripts/check_hardware.sh`.

The `apply_boot_fix.sh` script has been removed from this repository and must not be recreated.

## 7. Key Takeaways: What Not to Do in the Future

1. **Do not trust standard host OS settings for flashing**: Standard Ubuntu is built for consumer desktops, not pushing massive firmware blobs to embedded devices. Always expand the `usbfs_memory_mb` buffer and kill autosuspend before flashing a new Jetson.
2. **Do not rush a hardware reset**: If a low-level process (like flashing or a kernel panic) fails, an immediate reboot will often drag ghost errors into the next session. Always unplug the power and wait 60 seconds to drain the capacitors.
3. **Do not treat Tegra Linux like Desktop Linux**: The Jetson runs "L4T" (Linux for Tegra). Standard Ubuntu tutorials for installing headers, modifying GRUB, or tweaking kernel parameters will often fail or brick the device. Always look for Jetson-specific or L4T-specific documentation.
4. **Do not modify the bootloader without a physical backdoor**: Never edit `extlinux.conf` on internal eMMC storage unless you have a serial debug console attached to catch boot errors. Because the OS was smartly installed on an external USB drive, there was a backdoor to plug it into another computer and fix the typo.
