import threading
import time

import cv2
import numpy as np
from flask import Blueprint, Response

camera_bp = Blueprint("camera", __name__)


class CameraStream:
    def __init__(self, device: int = 0, width: int = 640, height: int = 480, fps: int = 30):
        self.device = device
        self.width = width
        self.height = height
        self.fps = fps
        self._cap: cv2.VideoCapture | None = None
        self._frame: bytes | None = None
        self._raw_bgr: np.ndarray | None = None
        self._lock = threading.Lock()
        self._running = False
        self._thread: threading.Thread | None = None
        self.error: str | None = None
        self.detection_enabled: bool = False
        self._detector = None

    def set_detector(self, detector):
        self._detector = detector

    def start(self) -> bool:
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
        last_time = time.perf_counter()
        while self._running:
            if self._cap is None or not self._cap.isOpened():
                break
            ret, frame = self._cap.read()
            if not ret:
                time.sleep(0.05)
                continue

            with self._lock:
                self._raw_bgr = frame.copy()

            t_now = time.perf_counter()
            fps = 1.0 / (t_now - last_time + 1e-6)
            last_time = t_now

            if self.detection_enabled and self._detector is not None and (self._detector.ready or getattr(self._detector, "mode", "") == "aruco"):
                annotated = self._detector.annotate_frame(frame)
            else:
                annotated = frame

            cv2.putText(annotated, f"FPS: {fps:.1f}", (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 1, (0, 255, 0), 2, cv2.LINE_AA)

            ok, jpeg = cv2.imencode(".jpg", annotated, [cv2.IMWRITE_JPEG_QUALITY, 75])
            if ok:
                with self._lock:
                    self._frame = jpeg.tobytes()

    def get_frame(self) -> bytes | None:
        with self._lock:
            return self._frame

    def get_raw_bgr(self) -> np.ndarray | None:
        with self._lock:
            return self._raw_bgr.copy() if self._raw_bgr is not None else None

    def stop(self):
        self._running = False
        if self._cap:
            self._cap.release()
            self._cap = None

    @property
    def ok(self) -> bool:
        return self._running and self._cap is not None and self._cap.isOpened()


_NO_SIGNAL_JPEG: bytes | None = None


def _make_no_signal_frame() -> bytes:
    global _NO_SIGNAL_JPEG
    if _NO_SIGNAL_JPEG:
        return _NO_SIGNAL_JPEG
    img = np.zeros((480, 640, 3), dtype="uint8")
    img[:] = (30, 30, 30)
    cv2.putText(img, "NO SIGNAL", (190, 230),
                cv2.FONT_HERSHEY_SIMPLEX, 1.8, (200, 200, 200), 3, cv2.LINE_AA)
    cv2.putText(img, "/dev/video0 not found", (170, 280),
                cv2.FONT_HERSHEY_SIMPLEX, 0.7, (140, 140, 140), 1, cv2.LINE_AA)
    _, enc = cv2.imencode(".jpg", img)
    _NO_SIGNAL_JPEG = enc.tobytes()
    return _NO_SIGNAL_JPEG


_camera: CameraStream | None = None


def init_camera(cam: CameraStream):
    global _camera
    _camera = cam


def _gen_frames():
    while True:
        frame = _camera.get_frame() if (_camera and _camera.ok) else _make_no_signal_frame()
        if frame:
            yield (
                b"--frame\r\n"
                b"Content-Type: image/jpeg\r\n\r\n" + frame + b"\r\n"
            )
        time.sleep(1 / 30)


@camera_bp.route("/video_feed")
def video_feed():
    return Response(_gen_frames(), mimetype="multipart/x-mixed-replace; boundary=frame")


@camera_bp.route("/camera_status")
def camera_status():
    if _camera:
        return {"ok": _camera.ok, "error": _camera.error, "device": _camera.device}
    return {"ok": False, "error": "Not initialised", "device": None}
