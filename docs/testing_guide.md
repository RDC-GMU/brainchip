# Testing Your Brainchip AKD1000 M.2 setup

After following the `README.md` to physically install the hardware and its associated `MetaTF` packages, you should verify the connection and driver installation are successful.

The `tests/` and `scripts/` directories include specific test scripts to validate your setup.

## 1. Validating Driver & PCIe connection (`check_hardware.sh`)

First, ensure the operating system detects your hardware and loads the required driver properly.

Run the hardware shell script:
```bash
./scripts/check_hardware.sh
```

**What this checks:**
- **PCIe Bus (`lspci`)**: Validates the Akida coprocessor operates on the host's PCI bus. If not found, your M.2 card is either loosely attached, missing power, or fundamentally incompatible with the socket.
- **Kernel Module (`lsmod`)**: Ensure `akida-pcie.ko` is properly built via DKMS and currently loaded by the OS.
- **Device Virtual Files (`/dev`)**: Ensures a special device file (`/dev/akidaX`) map exists, which is required for user-space access (your Python code) to communicate directly with hardware.

## 2. Validating MetaTF Stack (`test_akida.py`)

Once you verify the OS sees the hardware underneath, run the Python library tests to make sure `akida` software correctly parses and connects to the active execution device.

*Make sure your Python environment with `MetaTF` is active first.*

```bash
python tests/test_akida.py
```

**What this checks:**
- **Imports `akida` successfully**: Fails immediately if `akida` or underlying dependencies (e.g. `tensorflow`) throw errors.
- **Query hardware (`akida.devices()`)**: Uses `akida` to scan for execution nodes natively. It should print out descriptions indicating successful binding. If the output states it will use "software simulation," your hardware is not being identified by MetaTF.

## Troubleshooting

- **Hardware not found by `check_hardware.sh`**:
   - Reseat the AKD1000 M.2 unit into your motherboard's socket.
   - Verify the PCIE switch for your M.2 slot is not conflicting with another occupied port on the motherboard (common in ITX systems).

- **`akida-pcie` kernel module not found**:
   - Attempt to manually insert it using `sudo modprobe akida-pcie`.
   - If that fails, re-run `sudo make install` inside your driver folder, confirming there were no `gcc` or Linux headers compilation issues.

- **`test_akida.py` says Software Emulation**:
   - Ensure you add your user to any necessary groups (`video` or `dialout` or create `udev` rules based on documentation) so `MetaTF` isn't denied permission to write to `/dev/akida0`. Running the script once with `sudo python tests/test_akida.py` and seeing if it finds the hardware will confirm if it is a permissions issue.
