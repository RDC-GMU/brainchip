#!/usr/bin/env python3
"""
app.py — Entry point for the Brainchip AKD1000 Dashboard
=========================================================
Wires together Flask, SocketIO, the camera stream, system helpers,
the background monitor, and all WebSocket handlers.

Run:
    python3 src/app.py
"""

import os

from flask import Flask, render_template
from flask_socketio import SocketIO

from camera import CameraStream, camera_bp, init_camera
from monitor import start_monitor
from sockets import register_handlers
from system import get_akida_status, get_system_info

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

# ---------------------------------------------------------------------------
# Flask + SocketIO
# ---------------------------------------------------------------------------
app = Flask(__name__)
app.config["SECRET_KEY"] = "brainchip-akd1000-dashboard"
socketio = SocketIO(app, async_mode="threading", cors_allowed_origins="*")

# ---------------------------------------------------------------------------
# Camera
# ---------------------------------------------------------------------------
camera = CameraStream(device=0)
_cam_ok = camera.start()
if not _cam_ok:
    print(f"  [WARN] Camera not available: {camera.error}")

init_camera(camera)              # bind to blueprint routes
app.register_blueprint(camera_bp)

# ---------------------------------------------------------------------------
# WebSocket handlers & background monitor
# ---------------------------------------------------------------------------
register_handlers(socketio, BASE_DIR)

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
# Entry point
# ---------------------------------------------------------------------------
if __name__ == "__main__":
    start_monitor(socketio, camera)
    host, port = "0.0.0.0", 5000
    print("=" * 50)
    print(" BRAINCHIP AKD1000 — DASHBOARD")
    print(f" Camera : {'OK (/dev/video' + str(camera.device) + ')' if camera.ok else 'Not found'}")
    print(f" URL    : http://{host}:{port}")
    print("=" * 50)
    socketio.run(app, host=host, port=port, debug=False, allow_unsafe_werkzeug=True)
