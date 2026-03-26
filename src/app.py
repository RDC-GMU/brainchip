#!/usr/bin/env python3
"""
Brainchip AKD1000 Dashboard — Flask + WebSocket Server
======================================================
Real-time system monitoring, Akida hardware status, USB camera MJPEG stream,
object detection, and an interactive console.

Run:  python3 src/app.py
"""

import glob
import os
import platform
import subprocess
import threading
import time

import cv2
import psutil
from flask import Flask, Response, render_template
from flask_socketio import SocketIO, emit

# ---------------------------------------------------------------------------
# App setup
# ---------------------------------------------------------------------------
BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

app = Flask(__name__)
app.config["SECRET_KEY"] = "brainchip-akd1000-dashboard"
socketio = SocketIO(app, async_mode="threading", cors_allowed_origins="*")

# ---------------------------------------------------------------------------
# USB Camera
# ---------------------------------------------------------------------------

class CameraStream:
    """Thread-safe MJPEG capture from a USB camera via OpenCV."""

    def __init__(self, device: int = 0, width: int = 640, height: int = 480, fps: int = 30):
        self.device = device
        self.width = width
        self.height = height
        self.fps = fps
        self._cap: cv2.VideoCapture | None = None
        self._frame: bytes | None = None
        self._lock = threading.Lock()
        self._running = False
        self._thread: threading.Thread | None = None
        self.error: str | None = None

    def start(self):
        self._cap = cv2.VideoCapture(self.device)
        if not self._cap.isOpened():
            self.error = f"Could not open /dev/video{self.device}"
            return False
        self._cap.set(cv2.CAP_PROP_FRAME_WIDTH, self.width)
        self._cap.set(cv2.CAP_PROP_FRAME_HEIGHT, self.height)
        self._cap.set(cv2.CAP_PROP_FPS, self.fps)
        self._cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)
        self._running = True
        self._thread = threading.Thread(target=self._capture_loop, daemon=True)
        self._thread.start()
        return True

    def _capture_loop(self):
        while self._running:
            if self._cap is None or not self._cap.isOpened():
                break
            ret, frame = self._cap.read()
            if not ret:
                time.sleep(0.05)
                continue
            ret_enc, jpeg = cv2.imencode(
                ".jpg", frame,
                [cv2.IMWRITE_JPEG_QUALITY, 75]
            )
            if ret_enc:
                with self._lock:
                    self._frame = jpeg.tobytes()

    def get_frame(self) -> bytes | None:
        with self._lock:
            return self._frame

    def stop(self):
        self._running = False
        if self._cap:
            self._cap.release()
            self._cap = None

    @property
    def ok(self) -> bool:
        return self._running and self._cap is not None and self._cap.isOpened()


# Try to open the first available USB camera
camera = CameraStream(device=0)
_cam_ok = camera.start()
if not _cam_ok:
    print(f"  [WARN] Camera not available: {camera.error}")

# ---------------------------------------------------------------------------
# Camera streaming route
# ---------------------------------------------------------------------------

_NO_SIGNAL_JPEG: bytes | None = None

def _make_no_signal_frame() -> bytes:
    """Generate a static 'No Signal' JPEG when no camera is attached."""
    global _NO_SIGNAL_JPEG
    if _NO_SIGNAL_JPEG:
        return _NO_SIGNAL_JPEG
    import numpy as np
    img = np.zeros((480, 640, 3), dtype="uint8")
    img[:] = (30, 30, 30)
    cv2.putText(img, "NO SIGNAL", (190, 230), cv2.FONT_HERSHEY_SIMPLEX,
                1.8, (200, 200, 200), 3, cv2.LINE_AA)
    cv2.putText(img, "/dev/video0 not found", (170, 280),
                cv2.FONT_HERSHEY_SIMPLEX, 0.7, (140, 140, 140), 1, cv2.LINE_AA)
    _, enc = cv2.imencode(".jpg", img)
    _NO_SIGNAL_JPEG = enc.tobytes()
    return _NO_SIGNAL_JPEG


def _gen_frames():
    """MJPEG generator — yields boundary-delimited JPEG frames."""
    while True:
        frame = camera.get_frame() if camera.ok else _make_no_signal_frame()
        if frame:
            yield (
                b"--frame\r\n"
                b"Content-Type: image/jpeg\r\n\r\n" + frame + b"\r\n"
            )
        time.sleep(1 / 30)  # cap at ~30 fps


@app.route("/video_feed")
def video_feed():
    return Response(
        _gen_frames(),
        mimetype="multipart/x-mixed-replace; boundary=frame"
    )


@app.route("/camera_status")
def camera_status():
    return {"ok": camera.ok, "error": camera.error, "device": camera.device}


# ---------------------------------------------------------------------------
# System helpers
# ---------------------------------------------------------------------------

def get_cpu_temp():
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
                if line.lower().startswith(("model name", "hardware")):
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
    checks = {
        "pcie":   {"ok": False, "info": ""},
        "module": {"ok": False, "info": ""},
        "device": {"ok": False, "info": ""},
        "akida":  {"ok": False, "info": ""},
    }
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

    devs = glob.glob("/dev/akida*")
    if devs:
        checks["device"] = {"ok": True, "info": ", ".join(devs)}
    else:
        checks["device"]["info"] = "No /dev/akida* nodes"

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
    while True:
        try:
            mem = psutil.virtual_memory()
            disk = psutil.disk_usage("/")
            net = psutil.net_io_counters()
            socketio.emit("sys", {
                "cpu_all":  psutil.cpu_percent(),
                "mem_used": mem.used, "mem_total": mem.total, "mem_pct": mem.percent,
                "dsk_used": disk.used, "dsk_total": disk.total, "dsk_pct": disk.percent,
                "temp":     get_cpu_temp(),
                "uptime":   int(time.time() - psutil.boot_time()),
                "net_tx":   net.bytes_sent, "net_rx":   net.bytes_recv,
                "cam_ok":   camera.ok,
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
        cam_ok=camera.ok,
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
    cmd = (data.get("c") or "").strip()
    if not cmd:
        return
    if any(b in cmd.lower() for b in BLOCKED):
        emit("cmd_r", {"c": cmd, "o": "[BLOCKED] Command not permitted.", "err": True})
        return
    try:
        r = subprocess.run(
            cmd, shell=True, capture_output=True, text=True,
            timeout=30, cwd=BASE_DIR,
        )
        out = (r.stdout + r.stderr)[:8192] or "(no output)"
        emit("cmd_r", {"c": cmd, "o": out, "err": r.returncode != 0})
    except subprocess.TimeoutExpired:
        emit("cmd_r", {"c": cmd, "o": "Timed out (30 s).", "err": True})
    except Exception as e:
        emit("cmd_r", {"c": cmd, "o": str(e), "err": True})


@socketio.on("refresh_hw")
def on_refresh_hw():
    emit("hw", get_akida_status())


@socketio.on("run_script")
def on_run_script(data):
    script = data.get("s", "")
    allowed = {
        "check_hw":   ["bash", "scripts/check_hardware.sh"],
        "test_akida": ["python3", "tests/test_akida.py"],
        "detect":     ["python3", "tests/test_object_detection.py", "--threshold", "0.3"],
    }
    argv = allowed.get(script)
    if not argv:
        emit("script_r", {"s": script, "o": "Unknown script.", "err": True})
        return
    emit("script_r", {"s": script, "o": f"Running {' '.join(argv)} ...", "err": False, "starting": True})
    try:
        r = subprocess.run(
            argv, capture_output=True, text=True,
            timeout=120, cwd=BASE_DIR,
        )
        out = (r.stdout + r.stderr)[:16384] or "(no output)"
        emit("script_r", {"s": script, "o": out, "err": r.returncode != 0, "starting": False})
    except subprocess.TimeoutExpired:
        emit("script_r", {"s": script, "o": "Timed out (120 s).", "err": True, "starting": False})
    except Exception as e:
        emit("script_r", {"s": script, "o": str(e), "err": True, "starting": False})


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    socketio.start_background_task(_monitor)
    host, port = "0.0.0.0", 5000
    print("=" * 50)
    print(" BRAINCHIP AKD1000 — DASHBOARD")
    print(f" Camera: {'OK (/dev/video' + str(camera.device) + ')' if camera.ok else 'Not found'}")
    print(f" http://{host}:{port}")
    print("=" * 50)
    socketio.run(app, host=host, port=port, debug=False, allow_unsafe_werkzeug=True)
