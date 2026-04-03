#!/usr/bin/env python3

import os

from flask import Flask, render_template
from flask_socketio import SocketIO

from camera import CameraStream, camera_bp, init_camera
from detector import get_detector
from monitor import start_monitor
from sockets import register_handlers
from system import get_akida_status, get_system_info
from perception_engine import PerceptionEngine

BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

app = Flask(__name__)
app.config["SECRET_KEY"] = "brainchip-akd1000-dashboard"
socketio = SocketIO(app, async_mode="threading", cors_allowed_origins="*")

camera = CameraStream(device=0)
_cam_ok = camera.start()
if not _cam_ok:
    print(f"  [WARN] Camera not available: {camera.error}")

engine = PerceptionEngine()
engine.start()

detector = get_detector()
detector.engine = engine
camera.set_detector(detector)

init_camera(camera)
app.register_blueprint(camera_bp)

register_handlers(socketio, BASE_DIR, camera, detector)

@app.route("/")
def index():
    return render_template(
        "index.html",
        sys_info=get_system_info(),
        hw=get_akida_status(),
        cam_ok=camera.ok,
    )

if __name__ == "__main__":
    start_monitor(socketio, camera)
    
    def map_broadcast():
        while True:
            # Broadcast the map grid to the frontend UI
            with engine.grid_lock:
                # Compress the 60x60 grid into a flat list of integers for JSON web transmission
                grid_list = engine.occupancy_grid.flatten().tolist()
            socketio.emit("map_data", {"grid": grid_list, "size": 60})
            socketio.sleep(0.5)

    socketio.start_background_task(map_broadcast)
    
    host, port = "0.0.0.0", 5000
    print("=" * 50)
    print(" BRAINCHIP AKD1000 — DASHBOARD")
    print(f" Camera : {'OK (/dev/video' + str(camera.device) + ')' if camera.ok else 'Not found'}")
    print(f" URL    : http://{host}:{port}")
    print("=" * 50)
    socketio.run(app, host=host, port=port, debug=False, allow_unsafe_werkzeug=True)
