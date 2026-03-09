# Brainchip AKD1000 M.2 Test Scripts

The following table documents all scripts provided to help you verify and troubleshoot your hardware and software setup.

## Setup Scripts (`scripts/`)

| Script | Purpose | Run Command |
| :--- | :--- | :--- |
| `install_dependencies.sh` | Updates system packages and installs prerequisites (Python, pip, build tools). On Jetson, also installs `libhdf5-serial-dev` and creates a Python venv with `--system-site-packages`. | `./scripts/install_dependencies.sh` |
| `install_drivers.sh` | Clones the official `akida_dw_edma` driver repo, installs kernel headers (L4T-specific on Jetson), builds and loads the `akida_pcie` kernel module via `install.sh`. | `./scripts/install_drivers.sh` |
| `fix_jetson_pcie.sh` | Jetson-specific: Safe driver reload that disables ASPM and forces runtime PM to "always on" without triggering a PCIe bus rescan (which corrupts BAR mappings on Tegra). Also performs a BAR0 MMIO sanity check. | `sudo ./scripts/fix_jetson_pcie.sh` |
| `akida-pcie-fix.service` | Systemd service to run `fix_jetson_pcie.sh` automatically at every boot. | See [Jetson Guide](jetson_orin_nano.md) |

## Diagnostic & Verification Scripts

| Script | Purpose | Run Command |
| :--- | :--- | :--- |
| `check_hardware.sh` | Validates the full hardware stack: PCIe bus detection (`lspci`), kernel module (`lsmod`), device node (`/dev/akida*`), MetaTF CLI (`akida devices`), and BAR0 MMIO integrity. | `./scripts/check_hardware.sh` |
| `diagnose_pcie.sh` | Deep diagnostic tool. Collects full `lspci -vvv` output, PCIe register dumps, IOMMU/SMMU status, runtime PM state, and tests both MMIO (mmap) and DMA (pread) paths independently. Run this when `check_hardware.sh` fails. | `sudo ./scripts/diagnose_pcie.sh` |
| `resetpcie.sh` | Safe driver unload/reload for transient DMA errors (`RuntimeError: unexpected transfer len`). Does NOT do a PCIe bus rescan — critical on Jetson Tegra hardware. | `./scripts/resetpcie.sh` |

## Python Tests (`tests/`)

| Script | Purpose | Run Command |
| :--- | :--- | :--- |
| `test_akida.py` | Verifies the MetaTF Python package imports correctly and can bind to the physical hardware device (not software simulation). | `python3 tests/test_akida.py` |

## Recommended Execution Order

For a fresh install:

1. `./scripts/install_dependencies.sh`
2. `./scripts/install_drivers.sh`
3. *(Jetson only)* `sudo reboot`
4. `./scripts/check_hardware.sh`
5. `python3 tests/test_akida.py`

If `check_hardware.sh` fails:

1. `sudo ./scripts/diagnose_pcie.sh` — collect diagnostics
2. `sudo ./scripts/fix_jetson_pcie.sh` — for Jetson runtime PM issues
3. `./scripts/resetpcie.sh` — for transient DMA errors

See [testing_guide.md](testing_guide.md) for detailed troubleshooting per failure mode.
