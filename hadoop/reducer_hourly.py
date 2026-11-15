#!/usr/bin/env python3
"""
Hadoop Streaming Reducer: Hour-of-Day Load Profile (second MapReduce job)

Input (sorted by key):  Hour \t Interval_Energy_kWh \t Active_Power_kW
Output:                 Hour \t Total_Energy_kWh \t Reading_Count \t Avg_Power_kW \t Peak_Power_kW
"""

import sys


def emit(hour, energy, count, peak):
    avg_kw = (energy * 60.0 / count) if count else 0.0
    print(f"{hour}\t{energy:.4f}\t{count}\t{avg_kw:.4f}\t{peak:.3f}")


def main():
    current = None
    energy = 0.0
    count = 0
    peak = 0.0

    for line in sys.stdin:
        parts = line.strip().split("\t")
        if len(parts) < 3:
            continue
        try:
            kwh = float(parts[1])
            kw = float(parts[2])
        except ValueError:
            continue

        if parts[0] != current:
            if current is not None:
                emit(current, energy, count, peak)
            current, energy, count, peak = parts[0], 0.0, 0, 0.0

        energy += kwh
        count += 1
        if kw > peak:
            peak = kw

    if current is not None:
        emit(current, energy, count, peak)


if __name__ == "__main__":
    main()
