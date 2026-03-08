# Brainchip AKD1000 M.2 Guide

This repository contains documentation and requirements for setting up and using the **Brainchip AKD1000 M.2** neuromorphic ML accelerator card with the **MetaTF** framework.

## Detailed Guides
- **[NVIDIA Jetson Orin Nano Installation Guide](docs/jetson_orin_nano.md)**: specific compatibility notes and TensorFlow setup for the `aarch64` NVIDIA JetPack.
- **[Testing scripts documentation](docs/test_scripts.md)**: Details testing paths for verifying your hardware.

## 1. Hardware Requirements & Installation

1. **System Interface**:
   - The system requires a compatible x86-64 PC or an aarch64 architecture system (such as a Raspberry Pi 4). 
   - An available M.2 Key-M slot is necessary to install the card.

2. **Physical Installation**:
   - Always power down your system and unplug it before installing new hardware.
   - Insert the AKD1000 M.2 card into an available matching M.2 slot and secure it with the standoff screw.
   - Power on the system.

3. **Verify Connection** (Linux Systems):
   You can verify successful board detection by running the following command to check if the Akida coprocessor is being recognized on the PCIe bus:
   ```bash
   lspci | grep Co-processor
   ```
   *Expected Output*: Displays an entry for the Akida Neuromorphic hardware device.

## 2. Driver Installation

Before the AKD1000 can be used in your code, the proper driver module must be compiled and loaded into the kernel.

You can install the official akida kernel driver suite automatically utilizing the provided builder script:
```bash
./scripts/install_drivers.sh
```

Alternatively, you can manually clone the [BrainChip GitHub repository](https://github.com/Brainchip-Inc/akida_dw_edma) and build using `make` and `sudo ./install.sh`.

## 3. Software Environment & Dependencies

MetaTF is the machine learning framework used to build, train, quantize, and convert models to run on Akida neuromorphic hardware. 

1. **Python Environment Setup**: 
   - It is strongly advised to use Python between `3.10` and `3.12`.
   - Setup a dedicated virtual environment using `conda` or `venv` to avoid version conflicts.
   ```bash
   python -m venv akida_env
   source akida_env/bin/activate
   ```

2. **Install Package Requirements**:
   You can cleanly install the MetaTF suite and its TensorFlow dependencies using the `requirements.txt` file provided in this directory.

   ```bash
   pip install -r requirements.txt
   ```

   *Alternatively, install them manually using pip:*
   ```bash
   pip install tensorflow==2.15.0 keras==2.15.0
   pip install akida cnn2snn quantizeml akida-models
   ```

## 4. MetaTF Packages Overview

MetaTF consists of four core Python packages working seamlessly with TensorFlow:

- **`akida`**: The primary interface for simulating and interacting directly with the AKD1000 hardware execution unit. Includes the Hardware Abstraction Layer (HAL).
- **`quantizeml`**: A suite of tools to quantize Convolutional Neural Networks (CNNs) and Vision Transformers into low bit-width weight/activation representations optimized for edge execution.
- **`cnn2snn`**: Designed to convert standard AI models (such as floating-point or quantized Keras/TensorFlow graphs) into Akida-compatible structures.
- **`akida-models`**: Brainchip's Model Zoo providing access to pre-trained, quantized networks directly compatible with AKD architectures.

## 5. Usage Example

Here is a short Python script testing if the Akida M.2 device is available and accessible through your newly installed environment.

```python
import akida

available_devices = akida.devices()

print(f"Found {len(available_devices)} active Akida device(s).")

if available_devices:
    hardware_device = available_devices[0]
    print(f"Hardware initialization successful: {hardware_device.desc}")
else:
    print("Warning: No hardware found. Execution will fall back to software simulation mode.")
```