"""Minimal RGBA8 PNG reader/writer built on zlib + numpy.

PyPI is unreachable from this machine (TLS interception), so Pillow is not an
option. Only what the asset generators need is supported: 8-bit non-interlaced
PNGs, colour types 0/2/4/6, all five scanline filters.
"""

import struct
import zlib

import numpy as np

_CHANNELS = {0: 1, 2: 3, 4: 2, 6: 4}


def _chunks(data):
    pos = 8
    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos : pos + 4])
        tag = data[pos + 4 : pos + 8]
        yield tag, data[pos + 8 : pos + 8 + length]
        pos += 12 + length


def _unfilter(raw, width, height, channels):
    stride = width * channels
    out = np.zeros((height, stride), np.uint8)
    prev = np.zeros(stride, np.int32)
    pos = 0
    for y in range(height):
        ftype = raw[pos]
        line = np.frombuffer(raw[pos + 1 : pos + 1 + stride], np.uint8).astype(np.int32)
        pos += 1 + stride
        if ftype == 0:
            cur = line
        elif ftype == 1:
            cur = line.copy()
            for x in range(channels, stride):
                cur[x] = (cur[x] + cur[x - channels]) & 0xFF
        elif ftype == 2:
            cur = (line + prev) & 0xFF
        elif ftype == 3:
            cur = line.copy()
            for x in range(stride):
                left = cur[x - channels] if x >= channels else 0
                cur[x] = (cur[x] + ((left + prev[x]) >> 1)) & 0xFF
        elif ftype == 4:
            cur = line.copy()
            for x in range(stride):
                a = cur[x - channels] if x >= channels else 0
                b = prev[x]
                c = prev[x - channels] if x >= channels else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pred = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                cur[x] = (cur[x] + pred) & 0xFF
        else:
            raise ValueError(f"bad PNG filter {ftype}")
        out[y] = cur.astype(np.uint8)
        prev = cur
    return out.reshape(height, width, channels)


def read(path):
    """Read a PNG into an (h, w, 4) uint8 array."""
    data = open(path, "rb").read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path} is not a PNG")
    idat = b""
    width = height = colour = 0
    for tag, body in _chunks(data):
        if tag == b"IHDR":
            width, height, depth, colour, _, _, interlace = struct.unpack(">IIBBBBB", body)
            if depth != 8 or interlace or colour not in _CHANNELS:
                raise ValueError(f"{path}: unsupported PNG ({depth}bit type{colour})")
        elif tag == b"IDAT":
            idat += body
    px = _unfilter(zlib.decompress(idat), width, height, _CHANNELS[colour])
    if colour == 6:
        return px
    rgba = np.zeros((height, width, 4), np.uint8)
    rgba[..., 3] = 255
    if colour == 2:
        rgba[..., :3] = px
    elif colour == 0:
        rgba[..., :3] = px[..., :1]
    else:  # grey + alpha
        rgba[..., :3] = px[..., :1]
        rgba[..., 3] = px[..., 1]
    return rgba


def write(path, arr):
    """Write an (h, w, 4) uint8 array as an RGBA8 PNG."""
    arr = np.ascontiguousarray(arr, np.uint8)
    height, width = arr.shape[:2]
    raw = bytearray()
    for y in range(height):
        raw.append(0)
        raw += arr[y].tobytes()

    def chunk(tag, body):
        return (
            struct.pack(">I", len(body))
            + tag
            + body
            + struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF)
        )

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    open(path, "wb").write(png)


def box_downscale(arr, factor):
    """Average-pool an RGBA image by an integer factor, alpha-weighted."""
    h = arr.shape[0] // factor * factor
    w = arr.shape[1] // factor * factor
    src = arr[:h, :w].astype(np.float64)
    blocks = src.reshape(h // factor, factor, w // factor, factor, 4)
    alpha = blocks[..., 3:4]
    weight = alpha.sum(axis=(1, 3))
    colour = (blocks[..., :3] * alpha).sum(axis=(1, 3))
    out = np.zeros((h // factor, w // factor, 4), np.uint8)
    solid = weight[..., 0] > 0
    out[..., :3][solid] = np.clip(colour[solid] / weight[solid], 0, 255).astype(np.uint8)
    out[..., 3] = np.clip(alpha.mean(axis=(1, 3))[..., 0], 0, 255).astype(np.uint8)
    return out
