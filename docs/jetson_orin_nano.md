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

- **Recommended Version:** Use the latest stable NVidia JetPack (6.x series) running Ubuntu 22.04. 
- **Install Dependencies:** Setup the foundational compilers, Jetson-specific libraries, and Python configurations by running our provided installation script:
  ```bash
  ./scripts/install_dependencies.sh
  ```

## 3. TensorFlow on Jetson (Crucial Step)

Because the Jetson utilizes an ARM-based architecture with a Tegra GPU, you **cannot** simply run `pip install tensorflow` like on a standard desktop. You must install NVIDIA's specialized Jetson TensorFlow build *before* installing MetaTF, otherwise pip will install an incompatible CPU-only binary. Wait for the `install_dependencies.sh` script to successfully finish preparing your Jetson environment before proceeding.

1. Install the Official NVIDIA TensorFlow Wheel. Ensure the JetPack version matches the index URL.
   ```bash
   pip3 install --pre --extra-index-url https://developer.download.nvidia.com/compute/redist/jp/v60 dp-tensorflow
   ```
   *(Check the NVIDIA Developer Forums for the exact index link matching your specific JetPack OS version).*

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

With the specialized Jetson TensorFlow installed and the Brainchip drivers loaded, you can finally install MetaTF.

Instead of running `pip install -r requirements.txt` directly, install the MetaTF components manually to avoid overriding your Jetson-specific TensorFlow build:

```bash
pip3 install akida cnn2snn quantizeml akida-models
```

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
- **What Went Wrong**: Assuming the timeout was caused by standard Linux PCIe power management (ASPM) or the System Memory Management Unit (SMMU) blocking third-party access, the bootloader was modified by adding `pcie_aspm=off iommu.passthrough=1` to the `/boot/extlinux/extlinux.conf` file. However, the Orin Nano's ARM64 architecture is fiercely strict. Forcing IOMMU passthrough at the bootloader level on a Tegra kernel caused a catastrophic kernel panic during boot.
- **The Fix**: The 128GB external USB drive was pulled, mounted directly on another computer, and the bad kernel arguments were manually deleted from the text file to restore the boot sequence.

## 7. Key Takeaways: What Not to Do in the Future

1. **Do not trust standard host OS settings for flashing**: Standard Ubuntu is built for consumer desktops, not pushing massive firmware blobs to embedded devices. Always expand the `usbfs_memory_mb` buffer and kill autosuspend before flashing a new Jetson.
2. **Do not rush a hardware reset**: If a low-level process (like flashing or a kernel panic) fails, an immediate reboot will often drag ghost errors into the next session. Always unplug the power and wait 60 seconds to drain the capacitors.
3. **Do not treat Tegra Linux like Desktop Linux**: The Jetson runs "L4T" (Linux for Tegra). Standard Ubuntu tutorials for installing headers, modifying GRUB, or tweaking kernel parameters will often fail or brick the device. Always look for Jetson-specific or L4T-specific documentation.
4. **Do not modify the bootloader without a physical backdoor**: Never edit `extlinux.conf` on internal eMMC storage unless you have a serial debug console attached to catch boot errors. Because the OS was smartly installed on an external USB drive, there was a backdoor to plug it into another computer and fix the typo.
