"""
system.py — System and Akida hardware helpers
==============================================
All functions are pure (no Flask/SocketIO dependencies) so they can be
imported anywhere without circular-import risk.
"""

import glob
import platform
import subprocess

import psutil


def get_cpu_temp() -> float | None:
    """Read SoC temperature from the thermal sysfs interface."""
    for path in [
        "/sys/class/thermal/thermal_zone0/temp",
        "/sys/devices/virtual/thermal/thermal_zone0/temp",
    ]:
        try:
            with open(path) as f:
                return round(float(f.read().strip()) / 1000.0, 1)
        except (FileNotFoundError, ValueError):
            continue
    return None


def get_cpu_model() -> str:
    """Extract CPU model/hardware string from /proc/cpuinfo."""
    try:
        with open("/proc/cpuinfo") as f:
            for line in f:
                if line.lower().startswith(("model name", "hardware")):
                    return line.split(":", 1)[1].strip()
    except Exception:
        pass
    return platform.processor() or "Unknown"


def get_system_info() -> dict:
    return {
        "hostname":  platform.node(),
        "os":        f"{platform.system()} {platform.release()}",
        "arch":      platform.machine(),
        "python":    platform.python_version(),
        "cpu_count": psutil.cpu_count(),
        "cpu_model": get_cpu_model(),
    }


def get_akida_status() -> dict:
    """Probe all four layers of the Akida hardware stack."""
    checks = {
        "pcie":   {"ok": False, "info": ""},
        "module": {"ok": False, "info": ""},
        "device": {"ok": False, "info": ""},
        "akida":  {"ok": False, "info": ""},
    }

    # 1) PCIe bus
    try:
        r = subprocess.run(["lspci"], capture_output=True, text=True, timeout=5)
        for ln in r.stdout.splitlines():
            if any(k in ln.lower() for k in ("brainchip", "akida", "co-processor", "1e7c")):
                checks["pcie"] = {"ok": True, "info": ln.strip()}
                break
        if not checks["pcie"]["ok"]:
            checks["pcie"]["info"] = "No Akida device on PCIe bus"
    except Exception as e:
        checks["pcie"]["info"] = str(e)

    # 2) Kernel module
    try:
        r = subprocess.run(["lsmod"], capture_output=True, text=True, timeout=5)
        for ln in r.stdout.splitlines():
            if "akida" in ln.lower():
                checks["module"] = {"ok": True, "info": ln.split()[0]}
                break
        if not checks["module"]["ok"]:
            checks["module"]["info"] = "akida_pcie not loaded"
    except Exception as e:
        checks["module"]["info"] = str(e)

    # 3) Device node
    devs = glob.glob("/dev/akida*")
    if devs:
        checks["device"] = {"ok": True, "info": ", ".join(devs)}
    else:
        checks["device"]["info"] = "No /dev/akida* nodes"

    # 4) MetaTF / akida Python package
    try:
        import akida
        hw = akida.devices()
        if hw:
            checks["akida"] = {"ok": True, "info": f"{len(hw)} device(s) — {hw[0].desc}"}
        else:
            checks["akida"]["info"] = "Software emulation only"
    except ImportError:
        checks["akida"]["info"] = "akida package not installed"
    except Exception as e:
        checks["akida"]["info"] = str(e)

    return checks
