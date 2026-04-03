import os
import time
import threading
import warnings

import cv2
import numpy as np

os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")
warnings.filterwarnings("ignore", category=DeprecationWarning)

VOC_LABELS = [
    "aeroplane", "bicycle", "bird", "boat", "bottle",
    "bus", "car", "cat", "chair", "cow",
    "diningtable", "dog", "horse", "motorbike", "person",
    "pottedplant", "sheep", "sofa", "train", "tvmonitor",
]

_PALETTE = [
    (255, 56,  56),  (255, 157, 151), (255, 112,  31), (255, 178, 29),
    (207, 210,  49), (72,  249,  10), (146, 204,  23), (61,  219, 134),
    (26,  147, 52),  (0,   212, 187), (44,  153, 168), (0,   194, 255),
    (52,   69, 147), (100,  115, 255),(0,   24,  236), (132,  56, 255),
    (82,   0, 133),  (203,  56, 255), (255,  0,  192), (255,  56, 132),
]


class AkidaDetector:
    def __init__(self, score_threshold: float = 0.30):
        self.score_threshold = score_threshold
        self._lock = threading.Lock()
        self._model = None
        self._anchors = None
        self._hw_device = None
        self._loaded = False
        self._loading = False
        self._load_error: str | None = None
        self.last_inference_ms: float = 0.0
        self.last_detections: int = 0
        self.backend: str = "not loaded"
        self.mode: str = "both"
        self._last_annotate_time: float = 0.0
        self._fps: float = 0.0
        self.engine = None

    def load(self) -> bool:
        with self._lock:
            if self._loaded:
                return True
            if self._loading:
                return False
            self._loading = True

        try:
            import akida
            from cnn2snn import convert
            from akida_models import yolo_voc_pretrained
            from tf_keras import Model

            model_keras, anchors = yolo_voc_pretrained()

            if model_keras.layers[-1].name.lower() in ("yolo_output", "reshape"):
                compatible = Model(model_keras.input, model_keras.layers[-2].output)
            elif model_keras.layers[-1].__class__.__name__ == "Dequantizer":
                compatible = model_keras
            else:
                compatible = model_keras

            model_akida = convert(compatible)

            devices = akida.devices()
            hw_device = devices[0] if devices else None
            if hw_device:
                try:
                    model_akida.map(hw_device)
                    backend = f"AKD1000 · {hw_device.desc}"
                except Exception as e:
                    print(f"[detector] HW mapping failed: {e} — using emulation")
                    hw_device = None
                    backend = "software emulation"
            else:
                backend = "software emulation"

            with self._lock:
                self._model = model_akida
                self._anchors = anchors
                self._hw_device = hw_device
                self._loaded = True
                self._loading = False
                self._load_error = None
                self.backend = backend

            print(f"[detector] Loaded — {backend}")
            return True

        except Exception as exc:
            with self._lock:
                self._loading = False
                self._load_error = str(exc)
                self.backend = f"error: {exc}"
            print(f"[detector] Load failed: {exc}")
            return False

    def load_async(self):
        t = threading.Thread(target=self.load, daemon=True)
        t.start()

    @property
    def ready(self) -> bool:
        return self._loaded

    @property
    def loading(self) -> bool:
        return self._loading

    @property
    def load_error(self) -> str | None:
        return self._load_error

    def annotate_frame(self, bgr: np.ndarray) -> np.ndarray:
        try:
            out = bgr.copy()
            count = 0

            if self.mode in ("aruco", "both"):
                try:
                    aruco_dict = cv2.aruco.getPredefinedDictionary(cv2.aruco.DICT_6X6_250)
                    parameters = cv2.aruco.DetectorParameters()
                    aruco_detector = cv2.aruco.ArucoDetector(aruco_dict, parameters)
                    corners, ids, rejectedImgPoints = aruco_detector.detectMarkers(out)
                except AttributeError:
                    aruco_dict = cv2.aruco.Dictionary_get(cv2.aruco.DICT_6X6_250)
                    parameters = cv2.aruco.DetectorParameters_create()
                    corners, ids, rejectedImgPoints = cv2.aruco.detectMarkers(out, aruco_dict, parameters=parameters)
                
                if ids is not None:
                    cv2.aruco.drawDetectedMarkers(out, corners, ids)
                    count += len(ids)

            if self.mode in ("yolo", "both") and self._loaded and self._model is not None:
                from akida_models.detection.processing import preprocess_image, decode_output

                with self._lock:
                    model = self._model
                    anchors = self._anchors

                input_shape = model.layers[0].input_dims
                raw_h, raw_w = bgr.shape[:2]

                rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
                processed = preprocess_image(rgb, input_shape)
                batch = processed[np.newaxis, :].astype(np.uint8)

                t0 = time.perf_counter()
                pots = model.predict(batch)[0]
                t1 = time.perf_counter()
                inference_ms = (t1 - t0) * 1000

                h, w, _ = pots.shape
                num_anchors = len(anchors)
                num_classes = len(VOC_LABELS)
                pots = pots.reshape((h, w, num_anchors, 4 + 1 + num_classes))
                raw_boxes = decode_output(pots, anchors, num_classes)

                PERSON_CLASS_ID = VOC_LABELS.index("person")

                for box in raw_boxes:
                    score = box.get_score()
                    if score < self.score_threshold:
                        continue
                    cls_id = box.get_label()
                    if cls_id != PERSON_CLASS_ID:
                        continue
                    count += 1
                    color = _PALETTE[cls_id % len(_PALETTE)]
                    x1 = int(box.x1 * raw_w)
                    y1 = int(box.y1 * raw_h)
                    x2 = int(box.x2 * raw_w)
                    y2 = int(box.y2 * raw_h)

                    cv2.rectangle(out, (x1, y1), (x2, y2), color, 2)

                    label_text = f"{VOC_LABELS[cls_id]} {score:.0%}"
                    (tw, th), baseline = cv2.getTextSize(
                        label_text, cv2.FONT_HERSHEY_SIMPLEX, 0.55, 1
                    )
                    ty = max(y1 - 4, th + 4)
                    cv2.rectangle(out, (x1, ty - th - 4), (x1 + tw + 4, ty + baseline), color, -1)
                    cv2.putText(
                        out, label_text,
                        (x1 + 2, ty - 2),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.55, (255, 255, 255), 1, cv2.LINE_AA
                    )

                    if self.engine is not None:
                        # Simple placeholder translation mapping coordinates directly into ft
                        cx = (x1 + x2) / 2.0
                        cy = (y1 + y2) / 2.0
                        
                        cx_ft = (cx / raw_w) * 30.0
                        cy_ft = (cy / raw_h) * 30.0
                        self.engine.obstacle_detected(cx_ft, cy_ft)

                self.last_inference_ms = inference_ms
            else:
                if self.mode == "aruco":
                    self.last_inference_ms = 0.0

            self.last_detections = count
            return out

        except Exception as exc:
            print(f"[detector] annotate_frame error: {exc}")
            return bgr


_detector: AkidaDetector | None = None


def get_detector() -> AkidaDetector:
    global _detector
    if _detector is None:
        _detector = AkidaDetector()
    return _detector
