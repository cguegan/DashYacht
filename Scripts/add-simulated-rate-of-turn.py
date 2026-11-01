#!/usr/bin/env python3
"""Add a rate of turn, calculated from the own heading, to a Signal K replay file (one delta per line).

The Aava sample recording has no rate of turn for the own vessel (the "navigation.rateOfTurn"
values in it come from AIS targets). This script adds one value after each own heading update:
the slope of the heading over a window of ±5 s. Heading has a resolution of 0.001 rad and arrives
once per second, so the change between two updates alone would jump in steps of about 3.4 °/min.
Values use the Signal K source "simulated.rateOfTurn", so they are never mistaken for real data.
Running the script again replaces the previous simulated values.

Usage: python3 Scripts/add-simulated-rate-of-turn.py App/SampleData/aava-n2k-3min.jsonl
"""
import json
import math
import sys
from datetime import datetime

SOURCE = "simulated.rateOfTurn"
WINDOW_SECONDS = 5


def parse(timestamp):
    return datetime.fromisoformat(timestamp.replace("Z", "+00:00"))


def is_simulated(delta):
    return any(update.get("$source") == SOURCE for update in delta.get("updates", []))


def own_heading(delta):
    """(time, radians) of a heading update of the own vessel, or None. AIS deltas have a context."""
    if "context" in delta:
        return None
    for update in delta.get("updates", []):
        for item in update.get("values", []):
            if item["path"] == "navigation.headingTrue" and isinstance(item["value"], (int, float)):
                return parse(update["timestamp"]), item["value"]
    return None


def slope(points):
    """Least-squares slope of (seconds, radians) points, in rad/s."""
    n = len(points)
    mean_t = sum(t for t, _ in points) / n
    mean_h = sum(h for _, h in points) / n
    variance = sum((t - mean_t) ** 2 for t, _ in points)
    return sum((t - mean_t) * (h - mean_h) for t, h in points) / variance if variance else 0.0


def main(path):
    lines = [line if line.endswith("\n") else line + "\n" for line in open(path) if line.strip()]
    kept = [(line, json.loads(line)) for line in lines]
    kept = [(line, delta) for line, delta in kept if not is_simulated(delta)]

    # Unwrap the heading, so a pass through north (2π → 0) is not a full turn.
    headings = []
    for _, delta in kept:
        found = own_heading(delta)
        if found:
            time, value = found
            if headings:
                previous = headings[-1][1]
                value = previous + (value - previous + math.pi) % (2 * math.pi) - math.pi
            headings.append((time, value))
    start = headings[0][0]

    output, index = [], 0
    for line, delta in kept:
        output.append(line)
        found = own_heading(delta)
        if not found:
            continue
        time = headings[index][0]
        index += 1
        window = [((t - start).total_seconds(), h) for t, h in headings
                  if abs((t - time).total_seconds()) <= WINDOW_SECONDS]
        output.append(json.dumps({"updates": [{
            "$source": SOURCE,
            "timestamp": time.isoformat(timespec="milliseconds").replace("+00:00", "Z"),
            "values": [{"path": "navigation.rateOfTurn", "value": round(slope(window), 6)}],
        }]}, separators=(",", ":")) + "\n")

    with open(path, "w") as file:
        file.writelines(output)
    values = [json.loads(line)["updates"][0]["values"][0]["value"] for line in output if SOURCE in line]
    low, high = (math.degrees(v) * 60 for v in (min(values), max(values)))
    print(f"{path}: {len(values)} simulated rate of turn values added, {low:.1f} to {high:.1f} °/min")


if __name__ == "__main__":
    main(sys.argv[1])
