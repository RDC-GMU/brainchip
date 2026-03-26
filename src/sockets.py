"""
sockets.py — WebSocket event handlers
======================================
All @socketio.on() handlers registered via register_handlers().
Depends on: system.py (pure helpers), no circular imports.
"""

import subprocess

from flask_socketio import emit

from system import get_akida_status

# Commands that are never permitted regardless of user input
_BLOCKED = ("rm -rf /", "mkfs", "dd if=", ":(){", "shutdown", "reboot", "init 0")

# Predefined scripts that can be triggered from the dashboard
_ALLOWED_SCRIPTS: dict[str, list[str]] = {
    "check_hw":   ["bash", "scripts/check_hardware.sh"],
    "test_akida": ["python3", "tests/test_akida.py"],
    "detect":     ["python3", "tests/test_object_detection.py", "--threshold", "0.3"],
}


def register_handlers(socketio, base_dir: str):
    """Attach all WebSocket event handlers to the given SocketIO instance."""

    @socketio.on("connect")
    def on_connect():
        emit("hello", {"status": "ok"})

    @socketio.on("refresh_hw")
    def on_refresh_hw():
        emit("hw", get_akida_status())

    @socketio.on("cmd")
    def on_cmd(data):
        """Execute an arbitrary shell command — with a blocklist guard."""
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
        """Run a pre-approved script and stream its output."""
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
