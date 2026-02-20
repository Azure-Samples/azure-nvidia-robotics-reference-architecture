"""Flask-based diagnostic dashboard for real-time policy monitoring.

Runs in a background thread alongside the control loop,
streaming telemetry via Server-Sent Events (SSE) and serving
the single-page dashboard UI.
"""

from __future__ import annotations

import json
import logging
import socket
import threading
import time
from pathlib import Path

from flask import Flask, Response, jsonify, request, send_from_directory

from .telemetry import TelemetryStore

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Flask app factory
# ---------------------------------------------------------------------------

STATIC_DIR = Path(__file__).parent / "static"


def create_app(telemetry: TelemetryStore) -> Flask:
    """Create the Flask dashboard application."""
    app = Flask(__name__, static_folder=str(STATIC_DIR))
    app.config["telemetry"] = telemetry

    # Suppress Flask request logs in production
    wlog = logging.getLogger("werkzeug")
    wlog.setLevel(logging.WARNING)

    # ------------------------------------------------------------------
    # Routes
    # ------------------------------------------------------------------

    @app.route("/")
    def index():
        return send_from_directory(str(STATIC_DIR), "index.html")

    @app.route("/static/<path:filename>")
    def static_files(filename):
        return send_from_directory(str(STATIC_DIR), filename)

    # --- REST endpoints ---

    @app.route("/api/latest")
    def api_latest():
        """Return the latest telemetry snapshot."""
        store: TelemetryStore = app.config["telemetry"]
        return jsonify(store.get_latest())

    @app.route("/api/history")
    def api_history():
        """Return recent step history for plotting."""
        store: TelemetryStore = app.config["telemetry"]
        last_n = request.args.get("n", 300, type=int)
        return jsonify(store.get_history(last_n))

    @app.route("/api/trajectories")
    def api_trajectories():
        """Return per-joint trajectory arrays."""
        store: TelemetryStore = app.config["telemetry"]
        last_n = request.args.get("n", 300, type=int)
        return jsonify(store.get_joint_trajectories(last_n))

    @app.route("/api/camera")
    def api_camera():
        """Return the latest camera frame as JPEG."""
        store: TelemetryStore = app.config["telemetry"]
        jpeg = store.get_image_jpeg()
        if jpeg is None:
            return Response("No image available", status=404, headers={
                "Cache-Control": "no-cache, no-store, must-revalidate",
            })
        return Response(jpeg, mimetype="image/jpeg", headers={
            "Cache-Control": "no-cache, no-store, must-revalidate",
            "Content-Length": str(len(jpeg)),
        })

    @app.route("/api/camera/mjpeg")
    def api_camera_mjpeg():
        """Multipart JPEG stream for live camera feed.

        The browser renders this as a continuously updating image when
        used as an ``<img src="/api/camera/mjpeg">``.  Much more
        efficient than polling ``/api/camera`` with cache-busted URLs.
        """
        store: TelemetryStore = app.config["telemetry"]
        boundary = b"frame"

        def generate():
            while True:
                try:
                    jpeg = store.get_image_jpeg()
                    if jpeg is not None:
                        yield (
                            b"--" + boundary + b"\r\n"
                            b"Content-Type: image/jpeg\r\n"
                            b"Content-Length: " + str(len(jpeg)).encode() + b"\r\n"
                            b"\r\n" + jpeg + b"\r\n"
                        )
                except Exception as exc:
                    logger.debug("MJPEG frame error: %s", exc)
                # ~10 fps — balance between smoothness and bandwidth
                time.sleep(0.1)

        return Response(
            generate(),
            mimetype="multipart/x-mixed-replace; boundary=frame",
            headers={"Cache-Control": "no-cache, no-store"},
        )

    # --- SSE stream ---

    @app.route("/api/stream")
    def api_stream():
        """Server-Sent Events stream pushing telemetry at ~10 Hz."""
        store: TelemetryStore = app.config["telemetry"]

        def generate():
            while True:
                try:
                    data = store.get_latest()
                    yield f"data: {json.dumps(data)}\n\n"
                except Exception as exc:
                    logger.error("SSE serialization error: %s", exc)
                    yield f"data: {{}}\n\n"
                time.sleep(0.1)  # 10 Hz update rate for dashboard

        return Response(
            generate(),
            mimetype="text/event-stream",
            headers={
                "Cache-Control": "no-cache",
                "X-Accel-Buffering": "no",
            },
        )

    return app


# ---------------------------------------------------------------------------
# Background server launcher
# ---------------------------------------------------------------------------


def _check_port(host: str, port: int) -> bool:
    """Return True if *port* is available to bind."""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(1)
        try:
            s.bind((host if host != "0.0.0.0" else "", port))
            return True
        except OSError:
            return False


def start_dashboard(
    telemetry: TelemetryStore,
    host: str = "0.0.0.0",
    port: int = 5000,
) -> threading.Thread:
    """Start the dashboard server in a background daemon thread.

    Parameters
    ----------
    telemetry : TelemetryStore
        Shared telemetry store.
    host : str
        Bind address (0.0.0.0 for network access).
    port : int
        HTTP port.

    Returns
    -------
    threading.Thread
        The running server thread (daemon).
    """
    # Pre-flight check — fail loudly if the port is already taken by a
    # zombie process from a previous run.
    if not _check_port(host, port):
        logger.error(
            "Port %d is already in use!  Kill the previous process "
            "or choose a different --dashboard-port.",
            port,
        )
        raise OSError(f"Port {port} already in use")

    app = create_app(telemetry)
    _startup_ok = threading.Event()

    def _run():
        logger.info("Dashboard starting on http://%s:%d", host, port)
        try:
            _startup_ok.set()
            # Use threaded=True so SSE doesn't block other requests
            app.run(host=host, port=port, threaded=True, use_reloader=False)
        except Exception as exc:
            logger.error("Dashboard failed to start: %s", exc)
            _startup_ok.set()  # unblock caller even on failure

    thread = threading.Thread(target=_run, name="dashboard", daemon=True)
    thread.start()
    # Give the thread a moment to bind the port
    _startup_ok.wait(timeout=5)
    return thread
