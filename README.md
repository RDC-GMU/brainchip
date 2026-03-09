# Brainchip AKD1000 M.2 Guide

This repository contains documentation, scripts, and requirements for setting up and using the **Brainchip AKD1000 M.2** neuromorphic ML accelerator card with the **MetaTF** framework.

## Detailed Guides
- **[NVIDIA Jetson Orin NX Installation Guide](docs/jetson_orin_nano.md)**: Compatibility notes, TensorFlow setup for `aarch64` JetPack, and a full troubleshooting log including PCIe diagnostic procedures.
- **[Testing Scripts Documentation](docs/test_scripts.md)**: Details all scripts for verifying hardware and troubleshooting.
- **[Testing Guide](docs/testing_guide.md)**: Step-by-step verification and troubleshooting reference.

## 1. Hardware Requirements & Installation

1. **System Interface**:
   - Compatible with **x86-64** PCs or **aarch64** systems (Raspberry Pi 4, NVIDIA Jetson).
   - Requires an available **M.2 Key-M** slot (PCIe).

2. **Physical Installation**:
   - Always power down and unplug before installing new hardware.
   - Insert the AKD1000 M.2 card into the slot and secure with the standoff screw.
   - Power on the system.

3. **Verify Connection** (Linux):
   ```bash
   lspci | grep Co-processor
   ```
   *Expected*: `Co-processor: Brainchip Inc AKD1000 Neural Network Coprocessor [Akida] (rev 01)`

## 2. Driver Installation

Before the AKD1000 can be used, the kernel module must be compiled and loaded.

```bash
./scripts/install_drivers.sh
```

This clones the [Brainchip akida_dw_edma repository](https://github.com/Brainchip-Inc/akida_dw_edma) and runs its `install.sh`. Alternatively, clone and build manually:

```bash
git clone https://github.com/Brainchip-Inc/akida_dw_edma ~/akida_dw_edma
cd ~/akida_dw_edma && make && sudo ./install.sh
```

> **Note:** After every kernel update, you must re-run `install_drivers.sh` — the official Brainchip driver does not use DKMS.

## 3. Software Environment & Dependencies

MetaTF is the machine learning framework for building, training, quantizing, and running models on Akida hardware.

1. **Install System Dependencies**:
   ```bash
   ./scripts/install_dependencies.sh
   ```

2. **Python Environment** (Python 3.10–3.12 required):
   ```bash
   python -m venv akida_env
   source akida_env/bin/activate
   ```

3. **Install Package Requirements**:
   ```bash
   pip install -r requirements.txt
   ```

   Or manually:
   ```bash
   pip install tf-keras==2.19
   pip install akida==2.19.1 cnn2snn==2.19.1 akida-models==1.13.1
   ```

## 4. MetaTF Packages Overview

| Package | Purpose |
|---------|---------|
| `akida` | Primary hardware interface and HAL for the AKD1000 |
| `quantizeml` | Quantize CNNs/ViTs to low bit-width for edge execution |
| `cnn2snn` | Convert Keras/TF models to Akida-compatible format |
| `akida-models` | Pre-trained, quantized Brainchip model zoo |

## 5. Usage Example

```python
import akida

available_devices = akida.devices()
print(f"Found {len(available_devices)} active Akida device(s).")

if available_devices:
    hardware_device = available_devices[0]
    print(f"Hardware initialization successful: {hardware_device.desc}")
else:
    print("Warning: No hardware found. Falling back to software simulation mode.")
```

## 6. Verifying Your Setup

Run the hardware check and Python test in sequence:

```bash
./scripts/check_hardware.sh
python3 tests/test_akida.py
```

See [docs/testing_guide.md](docs/testing_guide.md) for full troubleshooting steps.

## 7. Jetson-Specific Notes

If running on a **Jetson Orin** and experiencing `Connection timed out` errors or `No Akida hardware devices found`, see the comprehensive troubleshooting guide in [docs/jetson_orin_nano.md](docs/jetson_orin_nano.md), which documents all known failure modes and their diagnostics including the x86 cross-test procedure.