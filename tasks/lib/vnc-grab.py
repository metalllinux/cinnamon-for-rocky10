#!/usr/bin/env python3
"""vnc-grab.py — minimal VNC (RFB) framebuffer grabber, host-side.

Part of the TASK-0008 login harness (planning doc
TASK-0008-cinnamon-gdm-auth-fix.md, work breakdown item 2). Host tool:
runs on the test host, connects to the guest's VNC display, grabs one
frame, writes a PNG. Test-only; never installed on the guest.

Why this exists: pixel evidence for the greeter/desktop. On libvirt-
managed VMs the harness uses `virsh screenshot`; the adopted orphan VM
(TASK-0008 item 2, attempt 4) has no domain record, so this grabber is
the observation channel. It also doubles as the pixel-evidence source
for any VM that exposes a VNC display.

Protocol: RFB 3.8, security types 2 (None) or 1 (VNC auth, no-password
QEMU: zero challenge, any response accepted). Encodings: raw (0) only,
declared via SetEncodings before the FramebufferUpdateRequest, so the
only pixel path to decode is raw.

Stdlib only (socket, struct, zlib). No third-party dependencies.

Usage: vnc-grab.py <host> <vnc-display-port> <out.png>
       (VNC display :N maps to TCP port 5900+N; pass the port)
Exit codes: 0 ok, 1 protocol/transport error, 2 usage.
"""

import struct
import socket
import sys
import zlib

RFB_VERSION = b"RFB 003.008\n"
ENCODING_RAW = 0


class ProtocolError(Exception):
    pass


def recv_exact(sock, n):
    buf = b""
    while len(buf) < n:
        chunk = sock.recv(n - len(buf))
        if not chunk:
            raise ConnectionError(f"connection closed after {len(buf)}/{n} bytes")
        buf += chunk
    return buf


def handshake(sock):
    """Version exchange + security handshake + ClientInit.
    Returns (width, height, PixelFormat, server name)."""
    srv_version = recv_exact(sock, 12)
    if not srv_version.startswith(b"RFB 003."):
        raise ProtocolError(f"unexpected server version {srv_version!r}")
    sock.sendall(RFB_VERSION)

    n_types = recv_exact(sock, 1)[0]
    types = list(recv_exact(sock, n_types))
    if 2 in types:  # None
        sock.sendall(b"\x02")
    elif 1 in types:  # VNC auth (no-password QEMU)
        sock.sendall(b"\x01")
        challenge = recv_exact(sock, 16)
        # No password set: QEMU accepts any response.
        sock.sendall(b"\x00" * 16)
        del challenge
    else:
        raise ProtocolError(f"no usable security type in {types}")

    result = recv_exact(sock, 1)[0]
    if result != 0:
        reason_len = recv_exact(sock, 4)[0]
        reason = recv_exact(sock, reason_len).decode("utf-8", "replace")
        raise ProtocolError(f"server refused connection: {reason}")

    sock.sendall(b"\x01")  # ClientInit: shared flag = 1

    fb = recv_exact(sock, 16)
    width, height = struct.unpack(">HH", fb[0:4])
    pf = fb[4:16]
    bpp, depth, big_endian, true_color = struct.unpack(">BBBB", pf[0:4])
    rmax, gmax, bmax = struct.unpack(">HHH", pf[4:10])
    rshift, gshift, bshift = struct.unpack(">BBB", pf[10:13])
    name_len = recv_exact(sock, 1)[0]
    name = recv_exact(sock, name_len).decode("utf-8", "replace")
    pixfmt = {
        "bpp": bpp, "depth": depth, "big_endian": big_endian,
        "true_color": true_color,
        "rshift": rshift, "gshift": gshift, "bshift": bshift,
        "rmax": rmax, "gmax": gmax, "bmax": bmax,
    }
    return width, height, pixfmt, name


def decode_pixel(u, pixfmt):
    r = (u >> pixfmt["rshift"]) & pixfmt["rmax"]
    g = (u >> pixfmt["gshift"]) & pixfmt["gmax"]
    b = (u >> pixfmt["bshift"]) & pixfmt["bmax"]
    # Scale 16-bit component maxima down to 8-bit.
    if pixfmt["rmax"] > 255:
        r = r * 255 // pixfmt["rmax"]
    if pixfmt["gmax"] > 255:
        g = g * 255 // pixfmt["gmax"]
    if pixfmt["bmax"] > 255:
        b = b * 255 // pixfmt["bmax"]
    return r, g, b


def grab_frame(sock, width, height, pixfmt):
    """Request and decode one full framebuffer. Returns an RGBA bytes
    buffer (row-major, 4 bytes/pixel, no padding)."""
    # Declare raw-only so the server never sends another encoding.
    sock.sendall(struct.pack(">BB", 2, 1) + struct.pack(">i", ENCODING_RAW))

    bpp = pixfmt["bpp"]
    bytes_pp = max(bpp // 8, 1)
    fmt = ">I" if not pixfmt["big_endian"] else "<I"

    sock.sendall(struct.pack(">2B4I", 3, 0, 0, 0, width, height))
    while True:
        msg = recv_exact(sock, 8)
        if msg[0] != 0:  # not a FramebufferUpdate
            raise ProtocolError(f"unexpected message type {msg[0]}")
        n_rects = struct.unpack(">H", msg[6:8])[0]
        rows = bytearray()
        for _ in range(n_rects):
            rx, ry, rw, rh, enc = struct.unpack(">HHHBB", recv_exact(sock, 10))
            if enc != ENCODING_RAW:
                raise ProtocolError(f"server sent encoding {enc}; only raw supported")
            data = recv_exact(sock, rw * rh * bytes_pp)
            for y in range(rh):
                for x in range(rw):
                    i = (y * rw + x) * bytes_pp
                    if bytes_pp == 4:
                        u = struct.unpack(fmt, data[i:i + 4])[0]
                    elif bytes_pp == 2:
                        u = struct.unpack(fmt, data[i:i + 2] + b"\x00\x00")[0]
                    else:
                        u = data[i]
                    r, g, b = decode_pixel(u, pixfmt)
                    rows.extend([r, g, b, 255])
        if not rows:
            raise ProtocolError("framebuffer update carried no rects")
        return bytes(rows)


def write_png(path, width, height, rgba):
    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        c += struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        return c

    raw = b""
    stride = width * 4
    for y in range(height):
        raw += b"\x00" + rgba[y * stride:(y + 1) * stride]
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", ihdr))
        f.write(chunk(b"IDAT", zlib.compress(raw, 6)))
        f.write(chunk(b"IEND", b""))


def main():
    if len(sys.argv) != 4:
        print(__doc__)
        return 2
    host, port, out = sys.argv[1], int(sys.argv[2]), sys.argv[3]
    try:
        with socket.create_connection((host, port), timeout=10) as sock:
            width, height, pixfmt, name = handshake(sock)
            rgba = grab_frame(sock, width, height, pixfmt)
        write_png(out, width, height, rgba)
    except (OSError, ProtocolError) as e:
        print(f"vnc-grab: {e}", file=sys.stderr)
        return 1
    print(f"vnc-grab: {width}x{height} from {host}:{port} "
          f"('{name}') -> {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
