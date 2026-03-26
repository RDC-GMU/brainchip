# Brainchip AKD1000 M.2 Test Scripts

The following table documents all scripts provided to help you verify and troubleshoot your hardware and software setup.

## Setup Scripts (`scripts/`)

| Script | Purpose | Run Command |
| :--- | :--- | :--- |
| `install_dependencies.sh` | Updates system packages, installs arm64 build libs, creates the `akida_env` Python venv, and installs all packages from `requirements.txt`. | `./scripts/install_dependencies.sh` |
| `install_drivers.sh` | Clones the official `akida_dw_edma` driver repo, installs `linux-headers` for the running kernel, patches the Makefile for kernel 6.x, and builds/loads the `akida_pcie` kernel module. | `./scripts/install_drivers.sh` |

## Diagnostic & Verification Scripts

| Script | Purpose | Run Command |
| :--- | :--- | :--- |
| `check_hardware.sh` | Validates the full hardware stack: PCIe bus detection (`lspci`), kernel module (`lsmod`), device node (`/dev/akida*`), MetaTF CLI (`akida devices`), and BAR0 MMIO integrity. | `./scripts/check_hardware.sh` |
| `diagnose_pcie.sh` | Deep diagnostic tool. Collects full `lspci -vvv` output, PCIe register dumps, IOMMU status, runtime PM state, and tests both MMIO (mmap) and DMA (pread) paths independently. Run this when `check_hardware.sh` fails. | `sudo ./scripts/diagnose_pcie.sh` |
| `resetpcie.sh` | Safe driver unload/reload for transient DMA errors (`RuntimeError: unexpected transfer len`). Does NOT do a PCIe bus rescan. | `./scripts/resetpcie.sh` |

## Python Tests (`tests/`)

| Script | Purpose | Run Command |
| :--- | :--- | :--- |
| `test_akida.py` | Verifies the MetaTF Python package imports correctly and can bind to the physical hardware device (not software simulation). | `python3 tests/test_akida.py` |
| `test_object_detection.py` | Runs YOLOv2 object detection using the pre-trained PASCAL-VOC model from the Akida model zoo. Supports custom images, confidence thresholds, and FPS benchmarking. | `python3 tests/test_object_detection.py` |

## Recommended Execution Order

For a fresh install:

1. `./scripts/install_dependencies.sh`
2. `./scripts/install_drivers.sh`
3. `sudo reboot`
4. `./scripts/check_hardware.sh`
5. `python3 tests/test_akida.py`
6. `python3 tests/test_object_detection.py`

If `check_hardware.sh` fails:

1. `sudo ./scripts/diagnose_pcie.sh` — collect diagnostics
2. `./scripts/resetpcie.sh` — for transient DMA errors

See [testing_guide.md](testing_guide.md) for detailed troubleshooting per failure mode.
