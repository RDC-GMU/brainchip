# Brainchip AKD1000 M.2 Test Scripts

The following table documents the test scripts provided in the `tests/` directory to help you quickly verify and troubleshoot your hardware and software setup.

| Script Name | Purpose | Run Command |
| :--- | :--- | :--- |
| `install_dependencies.sh` | Updates system packages and installs prerequisites like Python, pip, and Jetson-specific dependencies (if running on a Tegra-based architecture). | `./scripts/install_dependencies.sh` |
| `install_drivers.sh` | Automatically installs prerequisites, clones the Akida driver repository, builds, and loads the kernel module. | `./scripts/install_drivers.sh` |
| `resetpcie.sh` | Performs a warm bus remove and rescan for troubleshooting light timeouts (not recommended for deep ASPM sleep on Jetson). | `./scripts/resetpcie.sh` |

| `check_hardware.sh` | Validates the physical M.2 card installation, ensures the PCIe bus detects the device, checks that the `akida` kernel driver module is loaded, and confirms the `/dev/akida*` characters devices are created by the OS. | `./scripts/check_hardware.sh` |
| `test_akida.py` | Tests the MetaTF Python environment setup. It verifies the Python package imports correctly and successfully identifies and attaches to the physical hardware execution node rather than resorting to software simulation. | `python tests/test_akida.py` |

## Execution Order
It is highly recommended to run the scripts in the following order:
1. `./scripts/install_dependencies.sh` (To set up prerequisites)
2. `./scripts/install_drivers.sh` (If drivers are not yet installed)
3. `./scripts/check_hardware.sh`
4. `python tests/test_akida.py`

This ensures your kernel matches your physical hardware before you attempt to bind to it via Python. Both tests must report success for end-to-end hardware acceleration to function properly.
