# Brainchip AKD1000 M.2 — Raspberry Pi 5

This repository contains documentation, scripts, tests, and a real-time web dashboard for the **Brainchip AKD1000 M.2** neuromorphic ML accelerator running on a **Raspberry Pi 5**.

## Hardware

- **Host:** Raspberry Pi 5 (aarch64, Ubuntu 24.04 Server)
- **Accelerator:** Brainchip AKD1000 M.2 (PCIe, Key-M slot via HAT+)
- **Interface:** PCIe Gen 2 via the Pi 5's M.2 HAT+

Verify the card is visible on the bus:

```bash
lspci | grep Co-processor
# Expected: Co-processor: Brainchip Inc AKD1000 Neural Network Coprocessor [Akida] (rev 01)
```

## Quick Start

```bash
# 1. Install system deps + Python venv
./scripts/install_dependencies.sh

# 2. Activate env
source ~/akida_env/bin/activate

# 3. Install PCIe driver, then reboot
./scripts/install_drivers.sh
sudo reboot

# 4. After reboot — activate env and verify
source ~/akida_env/bin/activate
./scripts/check_hardware.sh

# 5. Run tests
python3 tests/test_akida.py
python3 tests/test_object_detection.py

# 6. Launch dashboard
python3 src/app.py
# → http://<pi-ip>:5000
```

## Software Stack

| Package | Version | Purpose |
|---------|---------|---------|
| `tf-keras` | 2.19 | Keras layer definitions (CPU only — Akida runs inference) |
| `akida` | 2.19.1 | Hardware HAL for AKD1000 |
| `cnn2snn` | 2.19.1 | Keras → Akida model conversion |
| `akida-models` | 1.13.1 | Pre-trained model zoo |
| `flask` + `flask-socketio` | latest | Dashboard web server |
| `psutil` | latest | System resource monitoring |
| `opencv-python-headless` | latest | USB camera capture (MJPEG) |
| `numpy`, `matplotlib`, `Pillow` | latest | Image I/O and visualization |

**System libraries required on Pi (installed by `install_dependencies.sh`):**

| Library | Purpose |
|---------|--------|
| `libgl1` | OpenGL stub — runtime dep of `opencv-python-headless` even in headless mode |
| `libglib2.0-0` | GLib runtime — required by OpenCV |
| `libopenblas-dev` | BLAS backend for NumPy |
| `libhdf5-dev` | HDF5 for model weights |

> **Note:** Python 3.10–3.12 required. MetaTF does not support Python 3.13+.

## Dashboard

The web dashboard provides real-time system monitoring and control:

- **System resources** — CPU, RAM, disk, temperature, uptime, network
- **Akida hardware status** — PCIe bus, kernel module, device node, MetaTF probe
- **Quick actions** — run hardware check, Akida test, or object detection from the browser
- **Interactive console** — shell access with command history

```bash
source ~/akida_env/bin/activate
python3 src/app.py
```

Open `http://<pi-ip>:5000` from any device on the same network.

## Tests

| Script | Purpose | Command |
|--------|---------|---------|
| `test_akida.py` | Verifies MetaTF imports and hardware binding | `python3 tests/test_akida.py` |
| `test_object_detection.py` | YOLOv2 inference on PASCAL-VOC (20 classes) | `python3 tests/test_object_detection.py` |

Detection test options:

```bash
python3 tests/test_object_detection.py --image photo.jpg   # custom image
python3 tests/test_object_detection.py --threshold 0.2     # lower confidence threshold
python3 tests/test_object_detection.py --benchmark 100     # FPS benchmark (100 frames)
```

## Troubleshooting

### Full hardware check

```bash
./scripts/check_hardware.sh
```

Verifies PCIe bus, kernel module, device node, MetaTF enumeration, and BAR0 MMIO integrity.

### `ImportError: libGL.so.1: cannot open shared object file`

`opencv-python-headless` still links against `libGL.so.1` at runtime. Fix:

```bash
sudo apt install -y libgl1 libglib2.0-0
```

`install_dependencies.sh` handles this automatically on fresh installs.

### Deep PCIe diagnostics

```bash
sudo ./scripts/diagnose_pcie.sh
```

### Transient DMA errors (`RuntimeError: unexpected transfer len`)

```bash
./scripts/resetpcie.sh
```

> **Important:** After every kernel update (`apt upgrade`), re-run `install_drivers.sh` — the driver does not use DKMS persistently across kernel upgrades on the Pi.

See [docs/testing_guide.md](docs/testing_guide.md) for full troubleshooting steps.