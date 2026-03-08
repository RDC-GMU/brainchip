import sys

try:
    import akida
    print("Success: 'akida' Python module loaded successfully.")
except ImportError:
    print("Error: The 'akida' python module is not installed.")
    print("   Please install the required packages using pip install -r requirements.txt")
    sys.exit(1)

def test_hardware_access():
    print("-" * 50)
    print("Testing Brainchip AKD1000 M.2 Hardware Connection")
    print("-" * 50)
    
    try:
        hw_devices = akida.devices()
        
        if not hw_devices:
            print("Warning: No Akida hardware devices found.")
            print("   The system will use the software emulation mode instead.")
            print("   If you have a physical unit connected, run 'scripts/check_hardware.sh' to troubleshoot.")
            return False
        
        num_devices = len(hw_devices)
        print(f"Success: Found {num_devices} Akida hardware device(s).")
        
        for index, device in enumerate(hw_devices):
            print(f"\n   Device [{index}]: {device.desc}")
        print("\nThe Brainchip AKD1000 M.2 hardware is connected and ready for use!")
        return True
    
    except Exception as e:
        print(f"\nError validating Akida hardware: {e}")
        return False

if __name__ == "__main__":
    test_hardware_access()
