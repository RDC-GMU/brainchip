#!/usr/bin/env python3
"""
Brainchip AKD1000 Object Detection Test
========================================
Uses the pre-trained YOLOv2 model from the akida-models zoo
(PASCAL-VOC 2007, AkidaNet 0.5 backbone) to run inference on a test image.

Supports:
  - AKD1000 hardware acceleration (auto-detected)
  - Software emulation fallback
  - Local image file or built-in VOC sample
  - Annotated output saved as PNG
  - FPS benchmarking

Run:
    python3 tests/test_object_detection.py                      # VOC sample
    python3 tests/test_object_detection.py --image photo.jpg    # custom image
    python3 tests/test_object_detection.py --benchmark 50       # 50-frame FPS test
"""

import sys
import os
import time
import argparse
import warnings

# ---------------------------------------------------------------------------
# 1.  Dependency Check
# ---------------------------------------------------------------------------
REQUIRED_PACKAGES = {
    "akida": "akida",
    "cnn2snn": "cnn2snn",
    "akida_models": "akida-models",
    "numpy": "numpy",
}

missing = []
for module, pip_name in REQUIRED_PACKAGES.items():
    try:
        __import__(module)
    except ImportError:
        missing.append(pip_name)

if missing:
    print("Error: Missing required Python packages:")
    for pkg in missing:
        print(f"   - {pkg}")
    print("\nInstall with:  pip install -r requirements.txt")
    sys.exit(1)

import numpy as np

# Silence TF/Keras verbose logging during model load
os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")
warnings.filterwarnings("ignore", category=DeprecationWarning)

import akida
from cnn2snn import convert
from akida_models import yolo_voc_pretrained
from akida_models.detection.processing import preprocess_image, decode_output

# PASCAL VOC class labels (20 classes)
VOC_LABELS = [
    "aeroplane", "bicycle", "bird", "boat", "bottle",
    "bus", "car", "cat", "chair", "cow",
    "diningtable", "dog", "horse", "motorbike", "person",
    "pottedplant", "sheep", "sofa", "train", "tvmonitor",
]

# ---------------------------------------------------------------------------
# 2.  Helper Functions
# ---------------------------------------------------------------------------

def check_hardware():
    """Detect Akida hardware and print status."""
    devices = akida.devices()
    if devices:
        dev = devices[0]
        print(f"   Hardware : {dev.desc}")
        print(f"   Devices  : {len(devices)} found")
        return dev
    else:
        print("   Hardware : None (using software emulation)")
        return None


def load_sample_image():
    """Load a sample image from the PASCAL-VOC dataset via TensorFlow Datasets."""
    try:
        import tensorflow_datasets as tfds
        print("   Loading PASCAL-VOC 2007 sample via tensorflow_datasets...")
        ds = tfds.load("voc/2007", split="validation", shuffle_files=True)
        sample = next(iter(ds.take(1)))
        image = sample["image"].numpy()
        print(f"   Image shape: {image.shape}")
        return image
    except Exception:
        # Fall back to a synthetic test image
        print("   tensorflow_datasets not available — generating synthetic test image")
        return generate_synthetic_image()


def generate_synthetic_image():
    """Create a 640x480 synthetic test image with colored rectangles."""
    img = np.zeros((480, 640, 3), dtype=np.uint8)
    # Sky gradient
    for y in range(240):
        blue = int(180 + (75 * y / 240))
        img[y, :] = [blue, int(blue * 0.7), int(blue * 0.3)]
    # Green ground
    img[240:, :] = [34, 139, 34]
    # Red rectangle (simulated object)
    img[100:200, 200:350] = [220, 50, 50]
    # Blue rectangle
    img[150:300, 400:520] = [50, 80, 200]
    # Yellow rectangle
    img[280:400, 100:250] = [230, 200, 50]
    return img


def load_image_file(path):
    """Load an image from a file path using PIL or TF."""
    try:
        from PIL import Image
        img = Image.open(path).convert("RGB")
        return np.array(img)
    except ImportError:
        pass
    try:
        import tensorflow as tf
        raw = tf.io.read_file(path)
        img = tf.image.decode_image(raw, channels=3)
        return img.numpy()
    except Exception:
        pass
    print(f"Error: Cannot load image '{path}'. Install Pillow:  pip install Pillow")
    sys.exit(1)


def run_detection(model_akida, image, anchors, labels, score_threshold=0.3):
    """
    Run object detection on a single image.
    Returns (pred_boxes, inference_time_ms).
    Each box: [x1, y1, x2, y2, class_id, score]
    """
    input_shape = model_akida.layers[0].input_dims
    raw_h, raw_w, _ = image.shape

    # Preprocess: resize + uint8
    processed = preprocess_image(image, input_shape)
    input_batch = processed[np.newaxis, :].astype(np.uint8)

    # Inference
    t0 = time.perf_counter()
    pots = model_akida.predict(input_batch)[0]
    t1 = time.perf_counter()
    inference_ms = (t1 - t0) * 1000

    # Decode
    h, w, c = pots.shape
    num_anchors = len(anchors)
    num_classes = len(labels)
    pots = pots.reshape((h, w, num_anchors, 4 + 1 + num_classes))
    raw_boxes = decode_output(pots, anchors, num_classes)

    # Rescale to original image dimensions and filter by score
    pred_boxes = []
    for box in raw_boxes:
        score = box.get_score()
        if score >= score_threshold:
            pred_boxes.append([
                box.x1 * raw_w,
                box.y1 * raw_h,
                box.x2 * raw_w,
                box.y2 * raw_h,
                box.get_label(),
                score,
            ])

    return np.array(pred_boxes) if pred_boxes else np.empty((0, 6)), inference_ms


def save_annotated_image(image, pred_boxes, labels, output_path):
    """Save the image with bounding boxes drawn on it."""
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        import matplotlib.patches as patches

        fig, ax = plt.subplots(1, figsize=(12, 8))
        ax.imshow(image)

        # Color palette for classes
        colors = plt.cm.tab20(np.linspace(0, 1, len(labels)))

        for box in pred_boxes:
            x1, y1, x2, y2 = box[0], box[1], box[2], box[3]
            cls_id = int(box[4])
            score = box[5]
            color = colors[cls_id % len(colors)]

            rect = patches.Rectangle(
                (x1, y1), x2 - x1, y2 - y1,
                linewidth=2, edgecolor=color, facecolor="none"
            )
            ax.add_patch(rect)
            ax.text(
                x1, y1 - 8,
                f"{labels[cls_id]} {score:.0%}",
                color="white", fontsize=9, fontweight="bold",
                bbox=dict(boxstyle="round,pad=0.2", facecolor=color, alpha=0.8),
            )

        ax.axis("off")
        plt.tight_layout()
        plt.savefig(output_path, dpi=150, bbox_inches="tight", pad_inches=0.05)
        plt.close(fig)
        print(f"   Saved annotated image → {output_path}")
        return True

    except ImportError:
        print("   Warning: matplotlib not installed — skipping image output.")
        print("   Install with:  pip install matplotlib")
        return False


def benchmark_fps(model_akida, image, anchors, labels, num_frames):
    """Run inference multiple times and report FPS statistics."""
    input_shape = model_akida.layers[0].input_dims
    processed = preprocess_image(image, input_shape)
    input_batch = processed[np.newaxis, :].astype(np.uint8)

    # Warm-up
    for _ in range(3):
        model_akida.predict(input_batch)

    times = []
    for i in range(num_frames):
        t0 = time.perf_counter()
        model_akida.predict(input_batch)
        t1 = time.perf_counter()
        times.append(t1 - t0)

    times = np.array(times) * 1000  # convert to ms
    fps_values = 1000.0 / times

    print(f"\n{'='*55}")
    print(f" Benchmark Results ({num_frames} frames)")
    print(f"{'='*55}")
    print(f"   Mean latency   : {times.mean():.2f} ms")
    print(f"   Std deviation   : {times.std():.2f} ms")
    print(f"   Min latency     : {times.min():.2f} ms")
    print(f"   Max latency     : {times.max():.2f} ms")
    print(f"   Mean FPS        : {fps_values.mean():.1f}")
    print(f"   Throughput range: {fps_values.min():.1f} – {fps_values.max():.1f} FPS")
    print(f"{'='*55}")


# ---------------------------------------------------------------------------
# 3.  Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Brainchip AKD1000 Object Detection Test",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""Examples:
  python3 tests/test_object_detection.py
  python3 tests/test_object_detection.py --image photo.jpg
  python3 tests/test_object_detection.py --benchmark 100
  python3 tests/test_object_detection.py --threshold 0.5 --output result.png
""",
    )
    parser.add_argument(
        "--image", "-i", type=str, default=None,
        help="Path to input image (default: use VOC sample or synthetic)"
    )
    parser.add_argument(
        "--output", "-o", type=str, default="detection_output.png",
        help="Path for annotated output image (default: detection_output.png)"
    )
    parser.add_argument(
        "--threshold", "-t", type=float, default=0.3,
        help="Detection confidence threshold (default: 0.3)"
    )
    parser.add_argument(
        "--benchmark", "-b", type=int, default=0,
        help="Run FPS benchmark with N frames (default: 0 = disabled)"
    )
    args = parser.parse_args()

    print("=" * 55)
    print(" Brainchip AKD1000 — Object Detection Test")
    print("=" * 55)
    print()

    # --- Step 1: Hardware check ---
    print("[1/5] Checking Akida hardware...")
    hw_device = check_hardware()
    print()

    # --- Step 2: Load pre-trained YOLO model ---
    print("[2/5] Loading pre-trained YOLOv2 model (PASCAL-VOC)...")
    print("   This downloads weights on first run (~15 MB)...")
    model_keras, anchors = yolo_voc_pretrained()
    num_classes = len(VOC_LABELS)
    num_anchors = len(anchors)
    print(f"   Model loaded: {num_classes} classes, {num_anchors} anchor boxes")
    print(f"   Input shape : {model_keras.input_shape}")
    print()

    # --- Step 3: Convert to Akida model ---
    print("[3/5] Converting Keras model to Akida format...")

    # The yolo_voc_pretrained model may already be in quantized form;
    # we need to remove any trailing non-essential layers that aren't
    # compatible with cnn2snn.convert (like Reshape/YOLO_output).
    from tf_keras import Model
    # Check if last layer is a reshape/output layer that should be removed
    if model_keras.layers[-1].name.lower() in ("yolo_output", "reshape"):
        compatible = Model(model_keras.input, model_keras.layers[-2].output)
    elif model_keras.layers[-1].__class__.__name__ == "Dequantizer":
        compatible = model_keras
    else:
        compatible = model_keras

    model_akida = convert(compatible)

    # Map to hardware if available
    if hw_device:
        try:
            model_akida.map(hw_device)
            print("   Model mapped to AKD1000 hardware ✓")
        except Exception as e:
            print(f"   Warning: Hardware mapping failed ({e})")
            print("   Falling back to software emulation.")
    else:
        print("   Using software emulation mode.")

    model_akida.summary()
    print()

    # --- Step 4: Load test image ---
    print("[4/5] Loading test image...")
    if args.image:
        if not os.path.isfile(args.image):
            print(f"   Error: File not found: {args.image}")
            sys.exit(1)
        image = load_image_file(args.image)
        print(f"   Loaded: {args.image} ({image.shape[1]}x{image.shape[0]})")
    else:
        image = load_sample_image()
    print()

    # --- Step 5: Run detection ---
    print("[5/5] Running object detection...")
    pred_boxes, inference_ms = run_detection(
        model_akida, image, anchors, VOC_LABELS,
        score_threshold=args.threshold
    )

    print(f"\n   Inference time: {inference_ms:.1f} ms ({1000/inference_ms:.1f} FPS)")
    print(f"   Detections    : {len(pred_boxes)} objects found")

    if len(pred_boxes) > 0:
        print()
        print(f"   {'Class':<15} {'Score':>6}   {'Bounding Box'}")
        print(f"   {'─'*15} {'─'*6}   {'─'*30}")
        for box in pred_boxes:
            cls_name = VOC_LABELS[int(box[4])]
            score = box[5]
            bbox = f"({box[0]:.0f}, {box[1]:.0f}) → ({box[2]:.0f}, {box[3]:.0f})"
            print(f"   {cls_name:<15} {score:>5.0%}   {bbox}")
    else:
        print("   No objects detected above threshold "
              f"({args.threshold:.0%}). Try lowering --threshold.")

    # Save annotated output
    print()
    save_annotated_image(image, pred_boxes, VOC_LABELS, args.output)

    # Optional benchmark
    if args.benchmark > 0:
        print(f"\n   Running FPS benchmark ({args.benchmark} frames)...")
        benchmark_fps(model_akida, image, anchors, VOC_LABELS, args.benchmark)

    print()
    backend = "AKD1000 hardware" if hw_device else "software emulation"
    print(f"✓ Object detection test complete ({backend}).")
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
