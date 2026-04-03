

import time

import psutil

from system import get_cpu_temp


def start_monitor(socketio, camera):
    socketio.start_background_task(_monitor_loop, socketio, camera)


def _monitor_loop(socketio, camera):
    while True:
        try:
            mem  = psutil.virtual_memory()
            disk = psutil.disk_usage("/")
            net  = psutil.net_io_counters()
            socketio.emit("sys", {
                "cpu_all":  psutil.cpu_percent(),
                "mem_used": mem.used,  "mem_total": mem.total,  "mem_pct": mem.percent,
                "dsk_used": disk.used, "dsk_total": disk.total, "dsk_pct": disk.percent,
                "temp":     get_cpu_temp(),
                "uptime":   int(time.time() - psutil.boot_time()),
                "net_tx":   net.bytes_sent,
                "net_rx":   net.bytes_recv,
                "cam_ok":   camera.ok if camera else False,
            })
        except Exception:
            pass
        socketio.sleep(2)
