#!/usr/bin/env python3
"""
Webcam -> RGB444 (160x120) -> UDP packets -> ESP32

Packet format (1284 bytes):
    byte 0    : frame_id   (0-255, wraps)
    byte 1    : start_line (0, 4, 8, ... 116)
    byte 2..3 : 0 (spare)
    byte 4..  : 4 lines x 320 bytes (160 pixels x 2 bytes per line)

Pixel layout, 2 bytes per pixel, pixels in left-to-right, top-to-bottom order:
    1st byte = 0 0 0 0 R3 R2 R1 R0
    2nd byte = G3 G2 G1 G0 B3 B2 B1 B0
The FPGA builds the 12-bit pixel as {1st_byte[3:0], 2nd_byte}.

Usage:
    python webcam_sender.py                    # real webcam, ESP32 in AP mode
    python webcam_sender.py --test             # moving colour bars, no camera
    python webcam_sender.py --ip 192.168.1.50  # ESP32 in STA mode
"""

import argparse
import os
import socket
import time

import cv2
import numpy as np

W, H = 160, 120
LINES_PER_PKT = 4
FPS = 30

# Make sure packing and packet size agree with the ESP32 and FPGA code.
BYTES_PER_LINE = W * 2                        # 320
PAYLOAD = BYTES_PER_LINE * LINES_PER_PKT      # 1280
assert H % LINES_PER_PKT == 0
assert 4 + PAYLOAD <= 1472                    # stay under the UDP MTU limit


def busy_wait_us(us: float) -> None:
    """Accurate short delay. time.sleep() is far too coarse on Windows."""
    end = time.perf_counter() + us / 1e6
    while time.perf_counter() < end:
        pass


def pack_rgb444(frame_bgr: np.ndarray) -> np.ndarray:
    """BGR frame (any size) -> array of shape (H, 320), dtype uint8.
    Each pixel becomes 2 bytes: [0000 R3..R0] [G3..G0 B3..B0]."""
    small = cv2.resize(frame_bgr, (W, H), interpolation=cv2.INTER_AREA)
    r = small[:, :, 2] >> 4
    g = small[:, :, 1] >> 4
    b = small[:, :, 0] >> 4
    out = np.empty((H, W, 2), dtype=np.uint8)
    out[:, :, 0] = r                  # 0000 RRRR
    out[:, :, 1] = (g << 4) | b       # GGGG BBBB
    return out.reshape(H, BYTES_PER_LINE)


def test_frame(n: int) -> np.ndarray:
    """8 colour bars with a white vertical line sweeping across (BGR)."""
    img = np.zeros((H, W, 3), dtype=np.uint8)
    bars_bgr = [(255, 255, 255), (0, 255, 255), (255, 255, 0), (0, 255, 0),
                (255, 0, 255), (0, 0, 255), (255, 0, 0), (0, 0, 0)]
    bw = W // 8
    for i, c in enumerate(bars_bgr):
        img[:, i * bw:(i + 1) * bw] = c
    img[:, (n * 2) % W] = (255, 255, 255)
    return img


def open_camera(index: int) -> cv2.VideoCapture:
    if os.name == "nt":
        cap = cv2.VideoCapture(index, cv2.CAP_DSHOW)
    else:
        cap = cv2.VideoCapture(index)
    cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)       # avoid showing stale frames
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
    cap.set(cv2.CAP_PROP_FPS, FPS)
    if not cap.isOpened():
        raise SystemExit("Could not open camera %d" % index)
    print("Camera reports %.1f fps (verify with the measured fps below)"
          % cap.get(cv2.CAP_PROP_FPS))
    return cap


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--ip", default="192.168.4.1", help="ESP32 IP address")
    ap.add_argument("--port", type=int, default=5005)
    ap.add_argument("--cam", type=int, default=0, help="camera index")
    ap.add_argument("--test", action="store_true", help="send colour bars, no camera")
    ap.add_argument("--preview", action="store_true", help="show a local window (adds latency)")
    ap.add_argument("--gap-us", type=float, default=800,
                    help="delay between packets; 30 packets x gap must be < 33 ms")
    args = ap.parse_args()

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 1 << 20)
    dest = (args.ip, args.port)

    cap = None if args.test else open_camera(args.cam)
    frame_id = 0
    sent_frames = 0
    t_report = time.perf_counter()
    next_frame_t = time.perf_counter()

    print("Sending to %s:%d  (Ctrl+C to stop)" % dest)
    try:
        while True:
            if args.test:
                # Pace to 30 Hz ourselves
                next_frame_t += 1.0 / FPS
                while time.perf_counter() < next_frame_t:
                    pass
                frame = test_frame(frame_id)
            else:
                # cap.read() blocks until the camera delivers the next frame,
                # so the camera itself paces us at its native rate.
                ok, frame = cap.read()
                if not ok:
                    continue

            lines = pack_rgb444(frame)
            for start in range(0, H, LINES_PER_PKT):
                header = bytes((frame_id & 0xFF, start, 0, 0))
                payload = lines[start:start + LINES_PER_PKT].tobytes()
                sock.sendto(header + payload, dest)
                busy_wait_us(args.gap_us)

            frame_id = (frame_id + 1) & 0xFF
            sent_frames += 1

            if args.preview:
                cv2.imshow("preview", frame)
                if cv2.waitKey(1) & 0xFF == ord("q"):
                    break

            now = time.perf_counter()
            if now - t_report >= 2.0:
                print("measured %.1f fps" % (sent_frames / (now - t_report)))
                sent_frames = 0
                t_report = now
    except KeyboardInterrupt:
        pass
    finally:
        if cap is not None:
            cap.release()
        cv2.destroyAllWindows()


if __name__ == "__main__":
    main()