#!/usr/bin/env python3
"""Add simulated engine data (two engines) to a Signal K replay file (one delta per line).

The Aava sample recording has no engine data. This script adds, for "propulsion.port" and
"propulsion.starboard", the revolutions (Hz), the gear ("Forward", "Neutral", "Reverse") and the
position of the engine control lever as requested revolutions ("revolutionsTarget", Hz, negative
astern; not a standard Signal K path). The lever moves at once; the engine follows it.
Each minute: both engines ahead, port astern, both in neutral, both ahead, starboard astern,
both in neutral. The gear changes only at idle, as on a real boat, and the RPM follows its
target with a lag of about 1.5 s.
Values use the Signal K source "simulated.engines", so they are never mistaken for real data.
Running the script again replaces the previous simulated values.

Usage: python3 Scripts/add-simulated-engines.py App/SampleData/aava-n2k-3min.jsonl
"""
import json
import math
import sys
from datetime import timedelta, datetime

SOURCE = "simulated.engines"
RATE_HZ = 2
IDLE = 750
LAG_SECONDS = 1.5

# (start second in the minute, (port gear, port RPM), (starboard gear, starboard RPM))
PLAN = [
    (0, ("Forward", 1500), ("Forward", 1500)),
    (15, ("Reverse", 1300), ("Forward", 1700)),
    (25, ("Neutral", IDLE), ("Neutral", IDLE)),
    (30, ("Forward", 1500), ("Forward", 1500)),
    (40, ("Forward", 1600), ("Reverse", 1100)),
    (50, ("Neutral", IDLE), ("Neutral", IDLE)),
]
# Seconds at idle before a gear change.
SHIFT_SECONDS = 2


def parse(timestamp):
    return datetime.fromisoformat(timestamp.replace("Z", "+00:00"))


def is_simulated(delta):
    return any(update.get("$source") == SOURCE for update in delta.get("updates", []))


def target(t, engine):
    """Gear and target RPM of one engine (0 port, 1 starboard) at t seconds."""
    phase = t % 60
    index = max(i for i, step in enumerate(PLAN) if step[0] <= phase)
    gear, rpm = PLAN[index][1 + engine]
    previous_gear = PLAN[index - 1][1 + engine][0]
    # Just before a gear change, come down to idle; just after it, stay at idle for a moment.
    next_start, next_gear = (PLAN[(index + 1) % len(PLAN)][0] or 60), PLAN[(index + 1) % len(PLAN)][1 + engine][0]
    if next_gear != gear and next_start - phase <= SHIFT_SECONDS + 1:
        return gear, IDLE
    if previous_gear != gear and phase - PLAN[index][0] < SHIFT_SECONDS:
        return gear, IDLE
    # Small load changes, so a steady engine does not look frozen.
    return gear, rpm + (15 * math.sin(2 * math.pi * t / 7 + engine) if gear != "Neutral" else 0)


def lever(t, engine):
    """Requested RPM from the lever of one engine at t seconds: the plan value, signed, 0 in neutral."""
    phase = t % 60
    gear, rpm = PLAN[max(i for i, step in enumerate(PLAN) if step[0] <= phase)][1 + engine]
    return {"Forward": rpm, "Reverse": -rpm, "Neutral": 0}[gear]


def main(path):
    lines = [line if line.endswith("\n") else line + "\n" for line in open(path) if line.strip()]
    kept = [(line, json.loads(line)) for line in lines]
    kept = [(line, delta) for line, delta in kept if not is_simulated(delta)]

    times = [parse(u["timestamp"]) for _, d in kept for u in d.get("updates", []) if "timestamp" in u]
    start, end = min(times), max(times)

    rpm = [IDLE, IDLE]
    step = timedelta(seconds=1 / RATE_HZ)
    keep = math.exp(-1 / RATE_HZ / LAG_SECONDS)
    next_time = start
    output = []

    def emit():
        t = (next_time - start).total_seconds()
        values = []
        for engine, name in enumerate(["port", "starboard"]):
            gear, goal = target(t, engine)
            rpm[engine] = goal + (rpm[engine] - goal) * keep
            values.append({"path": f"propulsion.{name}.revolutions", "value": round(rpm[engine] / 60, 3)})
            values.append({"path": f"propulsion.{name}.transmission.gear", "value": gear})
            values.append({"path": f"propulsion.{name}.revolutionsTarget", "value": round(lever(t, engine) / 60, 3)})
        output.append(json.dumps({"updates": [{
            "$source": SOURCE,
            "timestamp": next_time.isoformat(timespec="milliseconds").replace("+00:00", "Z"),
            "values": values,
        }]}, separators=(",", ":")) + "\n")

    for line, delta in kept:
        stamp = next((parse(u["timestamp"]) for u in delta.get("updates", []) if "timestamp" in u), None)
        while stamp is not None and next_time <= stamp and next_time <= end:
            emit()
            next_time += step
        output.append(line)

    with open(path, "w") as file:
        file.writelines(output)
    added = sum(1 for line in output if SOURCE in line)
    print(f"{path}: {added} simulated engine updates added")


if __name__ == "__main__":
    main(sys.argv[1])
