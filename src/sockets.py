import subprocess

from flask_socketio import emit

from system import get_akida_status

_BLOCKED = ("rm -rf /", "mkfs", "dd if=", ":(){", "shutdown", "reboot", "init 0")

_ALLOWED_SCRIPTS: dict[str, list[str]] = {
    "check_hw":   ["bash", "scripts/check_hardware.sh"],
    "test_akida": ["python3", "tests/test_akida.py"],
    "detect":     ["python3", "tests/test_object_detection.py", "--threshold", "0.3"],
}


def register_handlers(socketio, base_dir: str, camera=None, detector=None):

    @socketio.on("connect")
    def on_connect():
        emit("hello", {"status": "ok"})
        if detector is not None:
            emit("det_status", _det_status(detector))

    @socketio.on("refresh_hw")
    def on_refresh_hw():
        emit("hw", get_akida_status())

    @socketio.on("change_mode")
    def on_change_mode(data):
        if detector is not None:
            detector.mode = data.get("mode", "both")
            emit("det_status", _det_status(detector, camera))

    @socketio.on("toggle_detection")
    def on_toggle_detection(data):
        if camera is None or detector is None:
            emit("det_status", {"enabled": False, "ready": False, "loading": False,
                                "backend": "unavailable", "error": "no camera/detector"})
            return

        enable = bool(data.get("enable", True))

        if enable and detector.mode != "aruco" and not detector.ready and not detector.loading:
            emit("det_status", {"enabled": False, "ready": False, "loading": True,
                                "backend": "loading…", "error": None})

            def _load_and_notify():
                ok = detector.load()
                if ok or detector.mode == "aruco":
                    camera.detection_enabled = True
                socketio.emit("det_status", _det_status(detector, camera))

            socketio.start_background_task(_load_and_notify)
            return

        camera.detection_enabled = enable if detector.mode == "aruco" else (enable and detector.ready)
        emit("det_status", _det_status(detector, camera))

    @socketio.on("cmd")
    def on_cmd(data):
        cmd = (data.get("c") or "").strip()
        if not cmd:
            return
        if any(b in cmd.lower() for b in _BLOCKED):
            emit("cmd_r", {"c": cmd, "o": "[BLOCKED] Command not permitted.", "err": True})
            return
        try:
            r = subprocess.run(
                cmd, shell=True, capture_output=True, text=True,
                timeout=30, cwd=base_dir,
            )
            out = (r.stdout + r.stderr)[:8192] or "(no output)"
            emit("cmd_r", {"c": cmd, "o": out, "err": r.returncode != 0})
        except subprocess.TimeoutExpired:
            emit("cmd_r", {"c": cmd, "o": "Timed out (30 s).", "err": True})
        except Exception as e:
            emit("cmd_r", {"c": cmd, "o": str(e), "err": True})

    @socketio.on("run_script")
    def on_run_script(data):
        script = data.get("s", "")
        argv = _ALLOWED_SCRIPTS.get(script)
        if not argv:
            emit("script_r", {"s": script, "o": "Unknown script.", "err": True, "starting": False})
            return

        emit("script_r", {
            "s": script,
            "o": f"Running {' '.join(argv)} ...",
            "err": False,
            "starting": True,
        })

        try:
            r = subprocess.run(
                argv, capture_output=True, text=True,
                timeout=120, cwd=base_dir,
            )
            out = (r.stdout + r.stderr)[:16384] or "(no output)"
            emit("script_r", {"s": script, "o": out, "err": r.returncode != 0, "starting": False})
        except subprocess.TimeoutExpired:
            emit("script_r", {"s": script, "o": "Timed out (120 s).", "err": True, "starting": False})
        except Exception as e:
            emit("script_r", {"s": script, "o": str(e), "err": True, "starting": False})


def _det_status(detector, camera=None) -> dict:
    return {
        "enabled":      camera.detection_enabled if camera else False,
        "ready":        detector.ready,
        "loading":      detector.loading,
        "backend":      detector.backend,
        "error":        detector.load_error,
        "inference_ms": round(detector.last_inference_ms, 1),
        "detections":   detector.last_detections,
        "mode":         getattr(detector, "mode", "both"),
    }
