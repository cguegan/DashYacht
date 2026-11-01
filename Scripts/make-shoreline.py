#!/usr/bin/env python3
"""Convert the GSHHG full-resolution coastline into the shoreline file of the app.

Input: gshhs_f.b from gshhg-bin-2.3.7 (https://www.soest.hawaii.edu/pwessel/gshhg/, LGPL 3).
Kept: level 1 (land against sea) and level 5 (Antarctic ice front). Lakes, islands in lakes
and the Antarctic grounding line are not useful at sea.

The coast is stored as lines (not land polygons), cut into 1° × 1° cells, so the app reads
only the cells around the boat. A segment that crosses a cell edge is stored in both cells,
so the lines join without gaps. Segments longer than 0.25° are first split, so a point
outside its cell is never far from it.

Output format, little-endian:
  "DYSL", version (u8), cell count (u32),
  per cell, sorted by latitude then longitude: south edge (i16, degrees), west edge (i16),
      offset of its data from the start of the file (u32), length of its data (u32),
  then the data of each cell, compressed with raw DEFLATE (RFC 1951):
      line count, then per line: point count, then the points as (east, north) in units of
      1/16384° from the south-west corner of the cell; the first point as is, the next ones
      as the difference from the previous one. All numbers are zigzag LEB128 varints.

Usage: python3 Scripts/make-shoreline.py reference/gshhg/bin/gshhs_f.b App/Shoreline/shoreline.dysl
"""
import math
import struct
import sys
import zlib

UNITS = 16384  # per degree
MAX_STEP = 0.25  # degrees
TOLERANCE = 2  # units (about 14 m north–south): points closer than this to the line are dropped
KEPT_LEVELS = {1, 5}


def read_polygons(path):
    data = open(path, "rb").read()
    pos = 0
    while pos < len(data):
        header = struct.unpack(">11i", data[pos:pos + 44])
        pos += 44
        count, flag = header[1], header[2]
        points = struct.unpack(f">{2 * count}i", data[pos:pos + 8 * count])
        pos += 8 * count
        if flag & 255 in KEPT_LEVELS:
            coords = []
            for i in range(0, 2 * count, 2):
                lon = points[i] / 1e6
                coords.append((lon - 360 if lon >= 180 else lon, points[i + 1] / 1e6))
            yield coords


def cell(point):
    lon, lat = point
    return min(89, max(-90, math.floor(lat))), min(179, max(-180, math.floor(lon)))


def densify(p, q):
    """Points after p up to q (q itself last), at most MAX_STEP apart."""
    steps = math.ceil(max(abs(q[0] - p[0]), abs(q[1] - p[1])) / MAX_STEP)
    return [(p[0] + (q[0] - p[0]) * i / steps, p[1] + (q[1] - p[1]) * i / steps) for i in range(1, steps)] + [q]


def cut(polygons):
    """Lines per cell: {cell: [[point, ...], ...]}."""
    cells = {}
    for coords in polygons:
        ring = coords + coords[:1]
        current = {}  # cell -> line being extended
        for p, q in zip(ring, ring[1:]):
            if abs(q[0] - p[0]) > 180:
                continue  # crosses the antimeridian: dropped, the line restarts after it
            steps = densify(p, q)
            for a, b in zip([p] + steps[:-1], steps):
                for c in {cell(a), cell(b)}:
                    line = current.get(c)
                    if line is None or line[-1] is not a:
                        line = [a]
                        cells.setdefault(c, []).append(line)
                        current[c] = line
                    line.append(b)
    return cells


def simplify(points, tolerance):
    """Douglas–Peucker on integer points."""
    if len(points) < 3:
        return points
    keep = [False] * len(points)
    keep[0] = keep[-1] = True
    stack = [(0, len(points) - 1)]
    while stack:
        first, last = stack.pop()
        (x1, y1), (x2, y2) = points[first], points[last]
        dx, dy = x2 - x1, y2 - y1
        length = math.hypot(dx, dy)
        best, index = -1.0, None
        for i in range(first + 1, last):
            x, y = points[i]
            d = abs(dy * (x - x1) - dx * (y - y1)) / length if length else math.hypot(x - x1, y - y1)
            if d > best:
                best, index = d, i
        if index is not None and best > tolerance:
            keep[index] = True
            stack += [(first, index), (index, last)]
    return [p for p, k in zip(points, keep) if k]


def varint(value):
    value = (value << 1) ^ (value >> 63)  # zigzag
    out = bytearray()
    while True:
        byte = value & 0x7F
        value >>= 7
        if value:
            out.append(byte | 0x80)
        else:
            out.append(byte)
            return bytes(out)


def encode(south, west, lines):
    out = bytearray(varint(len(lines)))
    for line in lines:
        out += varint(len(line))
        px = py = 0
        for x, y in line:
            out += varint(x - px) + varint(y - py)
            px, py = x, y
    compressor = zlib.compressobj(9, zlib.DEFLATED, -15)  # raw DEFLATE
    return compressor.compress(bytes(out)) + compressor.flush()


def main(source, destination):
    cells = cut(read_polygons(source))
    blobs, total_points = [], 0
    for (south, west) in sorted(cells):
        lines = []
        for line in cells[(south, west)]:
            units = [(round((lon - west) * UNITS), round((lat - south) * UNITS)) for lon, lat in line]
            assert all(-32768 <= v <= 32767 for p in units for v in p), (south, west)
            simplified = simplify(units, TOLERANCE)
            if len(simplified) >= 2:
                lines.append(simplified)
                total_points += len(simplified)
        if lines:
            blobs.append((south, west, encode(south, west, lines)))

    header = b"DYSL" + struct.pack("<BI", 1, len(blobs))
    offset = len(header) + 12 * len(blobs)
    index = bytearray()
    for south, west, blob in blobs:
        index += struct.pack("<hhII", south, west, offset, len(blob))
        offset += len(blob)
    with open(destination, "wb") as file:
        file.write(header + bytes(index) + b"".join(blob for _, _, blob in blobs))
    print(f"{destination}: {len(blobs)} cells, {total_points} points, {offset / 1e6:.1f} MB")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
