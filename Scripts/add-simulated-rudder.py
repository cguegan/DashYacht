#!/usr/bin/env python3
"""Add a simulated rudder angle to a Signal K replay file (one delta per line).

The Aava sample recording has no rudder sensor, and the boat sails almost straight,
so a rudder derived only from the real rate of turn would barely move. This script adds:
  - small autopilot corrections (about ±5°, period 8 s),
  - one larger turn to port and one to starboard each minute (up to about 25°),
  - a part that follows the real rate of turn.
Values use the Signal K source "simulated.rudder", so they are never mistaken for real data.
Running the script again replaces the previous simulated values.

Usage: python3 Scripts/add-simulated-rudder.py App/SampleData/aava-n2k-3min.jsonl
"""
import json
import math
import sys
from datetime import datetime, timedelta

SOURCE = "simulated.rudder"
RATE_HZ = 5
MAX_DEGREES = 35


def parse(timestamp):
    return datetime.fromisoformat(timestamp.replace("Z", "+00:00"))


def is_simulated(delta):
    return any(update.get("$source") == SOURCE for update in delta.get("updates", []))


def rudder_degrees(t, rate_of_turn):
    autopilot = 5 * math.sin(2 * math.pi * t / 8)
    phase = t % 60
    turn = 0.0
    if 15 <= phase < 25:
        turn = -25 * math.sin(math.pi * (phase - 15) / 10)  # port
    elif 40 <= phase < 50:
        turn = 25 * math.sin(math.pi * (phase - 40) / 10)  # starboard
    follow = 20 * rate_of_turn  # degrees of rudder per °/s of rate of turn
    return max(-MAX_DEGREES, min(MAX_DEGREES, autopilot + turn + follow))


def main(path):
    lines = [line for line in open(path) if line.strip()]
    deltas = [json.loads(line) for line in lines]
    kept = [(line, delta) for line, delta in zip(lines, deltas) if not is_simulated(delta)]

    times = [parse(u["timestamp"]) for _, d in kept for u in d.get("updates", []) if "timestamp" in u]
    start, end = min(times), max(times)

    rate_of_turn = 0.0  # last real value, in °/s
    step = timedelta(seconds=1 / RATE_HZ)
    next_time = start
    output = []
    for line, delta in kept:
        stamp = next((parse(u["timestamp"]) for u in delta.get("updates", []) if "timestamp" in u), None)
        while stamp is not None and next_time <= stamp and next_time <= end:
            t = (next_time - start).total_seconds()
            value = math.radians(rudder_degrees(t, rate_of_turn))
            output.append(json.dumps({"updates": [{
                "$source": SOURCE,
                "timestamp": next_time.isoformat(timespec="milliseconds").replace("+00:00", "Z"),
                "values": [{"path": "steering.rudderAngle", "value": round(value, 4)}],
            }]}, separators=(",", ":")) + "\n")
            next_time += step
        for update in delta.get("updates", []):
            for item in update.get("values", []):
                if item["path"] == "navigation.rateOfTurn" and isinstance(item["value"], (int, float)):
                    rate_of_turn = math.degrees(item["value"])
        output.append(line if line.endswith("\n") else line + "\n")

    with open(path, "w") as file:
        file.writelines(output)
    added = sum(1 for line in output if SOURCE in line)
    print(f"{path}: {added} simulated rudder values added")


if __name__ == "__main__":
    main(sys.argv[1])
