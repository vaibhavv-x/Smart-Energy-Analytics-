#!/usr/bin/env python3
"""
Hadoop Streaming Mapper: Hour-of-Day Load Profile (second MapReduce job)

Reads the raw UCI file and emits one record per valid one-minute reading, keyed by
the hour of the day (00..23).

Input:  Date;Time;Global_active_power;...
Output: Hour \t Interval_Energy_kWh \t Active_Power_kW
"""

import sys


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line or line.startswith("Date;") or line.startswith("Date,"):
            continue

        delimiter = ";" if ";" in line else ","
        parts = line.split(delimiter)
        if len(parts) < 3:
            continue

        time_str = parts[1].strip()
        power_str = parts[2].strip()
        if power_str in ("?", "", "NA", "null", "NaN"):
            continue

        hour = time_str[:2]
        if len(time_str) < 5 or not hour.isdigit() or not 0 <= int(hour) <= 23:
            continue

        try:
            power_kw = float(power_str)
        except ValueError:
            continue

        # One-minute reading: kW * (1/60 h) = kWh
        print(f"{hour}\t{power_kw / 60.0:.6f}\t{power_kw:.3f}")


if __name__ == "__main__":
    main()
