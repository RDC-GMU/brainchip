#!/usr/bin/env python3
"""
Brainchip AKD1000 Dashboard — Flask + WebSocket Server
======================================================
Real-time system monitoring, Akida hardware status, object detection,
and an interactive console for the Brainchip AKD1000 M.2 accelerator.

Run:  python3 src/app.py
"""

import glob
import os
import platform
import subprocess
import time

import psutil
from flask import Flask, render_template
from flask_socketio import SocketIO, emit

# ---------------------------------------------------------------------------
# App setup
# ---------------------------------------------------------------------------
BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

app = Flask(__name__)
app.config["SECRET_KEY"] = "brainchip-akd1000-dashboard"
socketio = SocketIO(app, async_mode="threading", cors_allowed_origins="*")

# ---------------------------------------------------------------------------
# System helpers
# ---------------------------------------------------------------------------

def get_cpu_temp():
    """Read SoC temperature (Raspberry Pi / Jetson)."""
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


def get_cpu_model():
    try:
        with open("/proc/cpuinfo") as f:
            for line in f:
                if line.lower().startswith(("model", "hardware")):
                    return line.split(":", 1)[1].strip()
    except Exception:
        pass
    return platform.processor() or "Unknown"


def get_system_info():
    return {
        "hostname": platform.node(),
        "os": f"{platform.system()} {platform.release()}",
        "arch": platform.machine(),
        "python": platform.python_version(),
        "cpu_count": psutil.cpu_count(),
        "cpu_model": get_cpu_model(),
    }


def get_akida_status():
    """Probe all four layers of the Akida hardware stack."""
    checks = {
        "pcie":   {"ok": False, "info": ""},
        "module": {"ok": False, "info": ""},
        "device": {"ok": False, "info": ""},
        "akida":  {"ok": False, "info": ""},
    }
    # 1) PCIe
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
    # 4) Python akida package
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


# ---------------------------------------------------------------------------
# Background system monitor
# ---------------------------------------------------------------------------

def _monitor():
    """Emit system metrics every 2 seconds."""
    while True:
        try:
            mem = psutil.virtual_memory()
            disk = psutil.disk_usage("/")
            net = psutil.net_io_counters()
            socketio.emit("sys", {
                "cpu":      psutil.cpu_percent(percpu=True),
                "cpu_all":  psutil.cpu_percent(),
                "mem_used": mem.used, "mem_total": mem.total, "mem_pct": mem.percent,
                "dsk_used": disk.used, "dsk_total": disk.total, "dsk_pct": disk.percent,
                "temp":     get_cpu_temp(),
                "uptime":   int(time.time() - psutil.boot_time()),
                "net_tx":   net.bytes_sent, "net_rx":   net.bytes_recv,
            })
        except Exception:
            pass
        socketio.sleep(2)


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@app.route("/")
def index():
    return render_template(
        "index.html",
        sys_info=get_system_info(),
        hw=get_akida_status(),
    )


# ---------------------------------------------------------------------------
# WebSocket events
# ---------------------------------------------------------------------------

BLOCKED = ("rm -rf /", "mkfs", "dd if=", ":(){", "shutdown", "reboot", "init 0")

@socketio.on("connect")
def on_connect():
    emit("hello", {"status": "ok"})


@socketio.on("cmd")
def on_cmd(data):
    """Run a shell command and return output."""
    cmd = (data.get("c") or "").strip()
    if not cmd:
        return
    if any(b in cmd.lower() for b in BLOCKED):
        emit("cmd_r", {"c": cmd, "o": "⛔ Blocked for safety.", "err": True})
        return
    try:
        r = subprocess.run(
            cmd, shell=True, capture_output=True, text=True,
            timeout=30, cwd=BASE_DIR,
        )
        out = (r.stdout + r.stderr)[:8192] or "(no output)"
        emit("cmd_r", {"c": cmd, "o": out, "err": r.returncode != 0})
    except subprocess.TimeoutExpired:
        emit("cmd_r", {"c": cmd, "o": "⏱ Timed out (30 s).", "err": True})
    except Exception as e:
        emit("cmd_r", {"c": cmd, "o": str(e), "err": True})


@socketio.on("refresh_hw")
def on_refresh_hw():
    emit("hw", get_akida_status())


@socketio.on("run_script")
def on_run_script(data):
    """Run a predefined script and stream output."""
    script = data.get("s", "")
    allowed = {
        "check_hw":  ["bash", "scripts/check_hardware.sh"],
        "test_akida": ["python3", "tests/test_akida.py"],
        "detect":    ["python3", "tests/test_object_detection.py", "--threshold", "0.3"],
    }
    argv = allowed.get(script)
    if not argv:
        emit("script_r", {"s": script, "o": "Unknown script.", "err": True})
        return
    emit("script_r", {"s": script, "o": f"▶ Running {' '.join(argv)} …", "err": False})
    try:
        r = subprocess.run(
            argv, capture_output=True, text=True,
            timeout=120, cwd=BASE_DIR,
        )
        out = (r.stdout + r.stderr)[:16384] or "(no output)"
        emit("script_r", {"s": script, "o": out, "err": r.returncode != 0})
    except subprocess.TimeoutExpired:
        emit("script_r", {"s": script, "o": "⏱ Timed out (120 s).", "err": True})
    except Exception as e:
        emit("script_r", {"s": script, "o": str(e), "err": True})


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    socketio.start_background_task(_monitor)
    host, port = "0.0.0.0", 5000
    print("=" * 50)
    print(" BRAINCHIP AKD1000 — DASHBOARD")
    print(f" → http://{host}:{port}")
    print("=" * 50)
    socketio.run(app, host=host, port=port, debug=False, allow_unsafe_werkzeug=True)
