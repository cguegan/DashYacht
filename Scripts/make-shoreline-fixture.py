#!/usr/bin/env python3
"""Make the small shoreline file used by the BoatData tests, with Scripts/make-shoreline.py.

Synthetic GSHHG polygons (not real coast):
  - id 0, level 1: a square island from 59.9° to 60.1° N and 24.9° to 25.1° E, on the corner of four cells;
  - id 1, level 2: a lake from 10.2° to 10.4° N and 10.2° to 10.4° E, which must be left out;
  - id 2, level 1: a small island from 179.8° to 179.9° E at 0.2° to 0.3° N, next to the antimeridian.

Usage: python3 Scripts/make-shoreline-fixture.py Packages/DashYachtKit/Tests/BoatDataTests/Resources/shoreline-fixture.dysl
"""
import os
import runpy
import struct
import sys
import tempfile

POLYGONS = [
    (1, [(24.9, 59.9), (25.1, 59.9), (25.1, 60.1), (24.9, 60.1)]),
    (2, [(10.2, 10.2), (10.4, 10.2), (10.4, 10.4), (10.2, 10.4)]),
    (1, [(179.8, 0.2), (179.9, 0.2), (179.9, 0.3), (179.8, 0.3)]),
]


def gshhs(polygons):
    out = bytearray()
    for number, (level, points) in enumerate(polygons):
        lons, lats = [p[0] for p in points], [p[1] for p in points]
        micro = lambda v: round(v * 1e6)
        out += struct.pack(">11i", number, len(points), level, micro(min(lons)), micro(max(lons)),
                           micro(min(lats)), micro(max(lats)), 0, 0, -1, -1)
        for lon, lat in points:
            out += struct.pack(">2i", micro(lon), micro(lat))
    return bytes(out)


def main(destination):
    with tempfile.NamedTemporaryFile(suffix=".b", delete=False) as source:
        source.write(gshhs(POLYGONS))
    try:
        converter = runpy.run_path(os.path.join(os.path.dirname(__file__), "make-shoreline.py"))
        converter["main"](source.name, destination)
    finally:
        os.unlink(source.name)


if __name__ == "__main__":
    main(sys.argv[1])
