#!/usr/bin/env python3
"""
Run the HiveQL files on a real Apache Hive server (HiveServer2) through beeline.

  1. hive/schema.hql        creates the database, the raw external table and the analysis tables
  2. hive/build_tables.hql  preprocessing: builds the daily and hourly tables from the raw table
  3. hive/features.hql      builds the forecasting feature table with window functions
  4. hive/queries.hql       every query is run separately; results go to hive/cluster_results/
  5. exports the feature table to hive/cluster_results/daily_features.csv for the R scripts

Options:
  --build-only    only steps 1 to 3 (create the tables, preprocessing, features)
  --queries-only  only steps 4 and 5 (the 12 queries and the feature export)
  --show N        also print the first N rows of each query result

Needs HiveServer2 running (run_on_mac.sh starts it) and these environment variables:
  HIVE_HOME            Hive installation folder
  HIVE_JDBC_URL        optional, default jdbc:hive2://localhost:10000
"""

import argparse
import getpass
import os
import re
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
RESULTS_DIR = os.path.join(HERE, "cluster_results")
REPORT = os.path.join(HERE, "hive_cluster_report.md")
JDBC = os.environ.get("HIVE_JDBC_URL", "jdbc:hive2://localhost:10000")
DATABASE = "smart_energy_db"


def beeline(extra_args):
    hive_home = os.environ.get("HIVE_HOME")
    if not hive_home:
        sys.exit("HIVE_HOME is not set.")
    cmd = [os.path.join(hive_home, "bin", "beeline"), "-n", getpass.getuser(),
           "--silent=true", "--outputformat=csv2"] + extra_args
    return subprocess.run(cmd, capture_output=True, text=True)


def run_file(path):
    print(f"[*] Running {os.path.basename(path)} ...")
    start = time.time()
    res = beeline(["-u", JDBC, "-f", path])
    if res.returncode != 0:
        print(res.stderr[-3000:])
        sys.exit(f"[-] {os.path.basename(path)} failed.")
    print(f"[+] {os.path.basename(path)} finished in {time.time() - start:.1f}s")


def parse_queries(path):
    """Return [(number, title, sql)] for every 'Query N: title' block in the file."""
    text = open(path, encoding="utf-8").read()
    queries = []
    for match in re.finditer(r"-- Query (\d+): ([^\n]+)\n(.*?);", text, flags=re.S):
        number, title, body = int(match.group(1)), match.group(2).strip(), match.group(3)
        sql = "\n".join(l for l in body.split("\n") if not l.strip().startswith("--")).strip()
        queries.append((number, title, sql))
    return queries


def main():
    ap = argparse.ArgumentParser(description="Run the HiveQL files on HiveServer2.")
    group = ap.add_mutually_exclusive_group()
    group.add_argument("--build-only", action="store_true", help="only create the tables, preprocess and build features")
    group.add_argument("--queries-only", action="store_true", help="only run the 12 queries and export the features")
    ap.add_argument("--show", type=int, default=0, metavar="N", help="print the first N rows of each query result")
    args = ap.parse_args()

    os.makedirs(RESULTS_DIR, exist_ok=True)
    if not args.queries_only:
        run_file(os.path.join(HERE, "schema.hql"))
        run_file(os.path.join(HERE, "build_tables.hql"))
        run_file(os.path.join(HERE, "features.hql"))
        if args.build_only:
            return

    queries = parse_queries(os.path.join(HERE, "queries.hql"))
    report = ["# Apache Hive Execution Report (real cluster)", "",
              f"Executed through HiveServer2 (`{JDBC}`) with the MapReduce engine on YARN. "
              "Tables live in the Hive warehouse in HDFS (`/smart-energy/hive/warehouse`).", "",
              "| Query | Rows | Seconds |", "|---|---|---|"]
    details = []
    for number, title, sql in queries:
        print(f"  -> Query {number}: {title}")
        start = time.time()
        res = beeline(["-u", f"{JDBC}/{DATABASE}", "-e", sql])
        elapsed = time.time() - start
        if res.returncode != 0:
            print(res.stderr[-3000:])
            sys.exit(f"[-] Query {number} failed.")
        lines = [l for l in res.stdout.split("\n") if l.strip()]
        out = os.path.join(RESULTS_DIR, f"q{number:02d}.csv")
        with open(out, "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
        rows = max(len(lines) - 1, 0)
        print(f"     {rows} rows in {elapsed:.1f}s -> {os.path.relpath(out, os.path.dirname(HERE))}")
        if args.show:
            for line in lines[:args.show + 1]:
                print("       " + line.replace(",", "  |  "))
            if rows > args.show:
                print(f"       ... {rows - args.show} more rows")
        report.append(f"| Q{number}: {title} | {rows} | {elapsed:.1f} |")
        details += [f"## Query {number}: {title}", "", "```sql", sql, "```", "",
                    f"Result file: `hive/cluster_results/q{number:02d}.csv` ({rows} rows). First rows:", "",
                    "```", *lines[:11], "```", ""]

    # Feature table for the R forecasting script
    print("  -> Exporting daily_features")
    res = beeline(["-u", f"{JDBC}/{DATABASE}", "-e", "SELECT * FROM daily_features ORDER BY consumption_date"])
    if res.returncode != 0:
        print(res.stderr[-3000:])
        sys.exit("[-] Feature export failed.")
    lines = [l for l in res.stdout.split("\n") if l.strip()]
    lines[0] = ",".join(c.split(".")[-1] for c in lines[0].split(","))   # drop the table prefix from column names
    with open(os.path.join(RESULTS_DIR, "daily_features.csv"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    print(f"     {len(lines) - 1} rows -> hive/cluster_results/daily_features.csv")
    report += ["", f"The forecasting feature table (`daily_features`, {len(lines) - 1} rows) is exported to "
               "`hive/cluster_results/daily_features.csv` for the R scripts."]

    with open(REPORT, "w", encoding="utf-8") as f:
        f.write("\n".join(report + [""] + details))
    print(f"[+] {len(queries)} queries executed on Hive. Report: {os.path.relpath(REPORT, os.path.dirname(HERE))}")


if __name__ == "__main__":
    main()
