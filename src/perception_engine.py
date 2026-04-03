import cv2
import numpy as np
import threading
import queue
import socket
import time
import sys

FIELD_SIZE_FT = 30.0
CELL_SIZE_FT  = 0.5
GRID_SIZE     = int(FIELD_SIZE_FT / CELL_SIZE_FT)

JETSON_IP             = "192.168.1.100"
JETSON_PORT           = 5005
UDP_BROADCAST_RATE_HZ = 10.0

class PerceptionEngine:
    def __init__(self):
        self.occupancy_grid = np.zeros((GRID_SIZE, GRID_SIZE), dtype=np.uint8)
        self.grid_lock = threading.Lock()
        self.local_obstacle_queue = queue.Queue(maxsize=100)
        self.running = False
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

    def start(self):
        self.running = True
        
        self.uav_thread = threading.Thread(target=self._uav_video_loop, daemon=True)
        self.uav_thread.start()
        
        self.fusion_thread = threading.Thread(target=self._sensor_fusion_loop, daemon=True)
        self.fusion_thread.start()
        
        self.tx_thread = threading.Thread(target=self._transmission_loop, daemon=True)
        self.tx_thread.start()

        print("[Engine] All perception and data-link threads successfully started.")

    def stop(self):
        self.running = False
        if hasattr(self, 'sock'):
            self.sock.close()
        print("[Engine] System resources released. Stopped gracefully.")

    def _uav_video_loop(self):
        pipeline = "udpsrc port=5000 ! application/x-rtp, payload=96 ! rtph264depay ! h264parse ! v4l2h264dec ! videoconvert ! appsink drop=true max-buffers=1"
        
        try:
            cap = cv2.VideoCapture(pipeline, cv2.CAP_GSTREAMER)
        except Exception:
            cap = None

        src_points = np.float32([[100, 100], [540, 100], [0, 480], [640, 480]])
        dst_points = np.float32([[0, 0], [GRID_SIZE, 0], [0, GRID_SIZE], [GRID_SIZE, GRID_SIZE]])
        M_warp = cv2.getPerspectiveTransform(src_points, dst_points)

        while self.running:
            if cap is None or not cap.isOpened():
                time.sleep(1.0)
                try:
                    cap = cv2.VideoCapture(pipeline, cv2.CAP_GSTREAMER)
                except Exception:
                    pass
                continue
                
            ret, frame = cap.read()
            if not ret:
                time.sleep(0.01)
                continue
                
            warped = cv2.warpPerspective(frame, M_warp, (GRID_SIZE, GRID_SIZE))
            
            gray = cv2.cvtColor(warped, cv2.COLOR_BGR2GRAY)
            _, thresh = cv2.threshold(gray, 60, 1, cv2.THRESH_BINARY_INV)
                
            self._latest_uav_grid = thresh.astype(np.uint8)

        cap.release()

    def obstacle_detected(self, x_feet, y_feet):
        try:
            self.local_obstacle_queue.put_nowait((x_feet, y_feet))
        except queue.Full:
            pass

    def _sensor_fusion_loop(self):
        local_layer = np.zeros((GRID_SIZE, GRID_SIZE), dtype=np.uint8)
        
        while self.running:
            while not self.local_obstacle_queue.empty():
                try:
                    x_ft, y_ft = self.local_obstacle_queue.get_nowait()
                    
                    col = int(x_ft / CELL_SIZE_FT)
                    row = int(y_ft / CELL_SIZE_FT)
                    
                    if 0 <= col < GRID_SIZE and 0 <= row < GRID_SIZE:
                        local_layer[row, col] = 1
                except queue.Empty:
                    break

            with self.grid_lock:
                if hasattr(self, '_latest_uav_grid'):
                    self.occupancy_grid = np.maximum(self._latest_uav_grid, local_layer)
                else:
                    self.occupancy_grid = local_layer.copy()

            time.sleep(0.05)

    def _transmission_loop(self):
        rate = 1.0 / UDP_BROADCAST_RATE_HZ
        while self.running:
            t_start = time.perf_counter()
            
            with self.grid_lock:
                grid_data = self.occupancy_grid.tobytes()
            
            try:
                self.sock.sendto(grid_data, (JETSON_IP, JETSON_PORT))
            except socket.error:
                pass
                
            elapsed = time.perf_counter() - t_start
            sleep_time = max(0.0, rate - elapsed)
            time.sleep(sleep_time)


if __name__ == "__main__":
    engine = PerceptionEngine()
    engine.start()
    
    print(f"[Main] Field Specs: {FIELD_SIZE_FT}x{FIELD_SIZE_FT}ft -> Grid Space: ({GRID_SIZE}x{GRID_SIZE} Cells)")
    print(f"[Main] Broadcasting occupancy matrix to: {JETSON_IP} : {JETSON_PORT}")
    print("[Main] Execution loop armed. Press Ctrl+C at any time to execute shutdown procedures.")
    
    try:
        while True:
            engine.obstacle_detected(15.0, 12.5) 
            time.sleep(0.5)
            
    except KeyboardInterrupt:
        print("\n[Main] Shutdown signal detected. Instructing cleanup protocol...")
    finally:
        engine.stop()
        print("[Main] Routine terminated cleanly.")
