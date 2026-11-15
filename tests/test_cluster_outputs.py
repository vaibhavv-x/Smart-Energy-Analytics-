"""
Automated Tests: outputs of the jobs that ran on the Hadoop cluster
(MapReduce on YARN and Apache Hive). Each test is skipped when its output file
does not exist yet, i.e. before `bash run_on_mac.sh` has been run.
"""

import os

import numpy as np
import pandas as pd
import pytest

DAILY_CSV = os.path.join("data", "processed", "daily_energy_consumption.csv")
MR_DAILY = os.path.join("hadoop", "mapreduce_yarn_daily_output.txt")
MR_HOURLY = os.path.join("hadoop", "mapreduce_yarn_hourly_output.txt")
HIVE_DIR = os.path.join("hive", "cluster_results")


def need(path):
    if not os.path.exists(path):
        pytest.skip(f"{path} not found; run bash run_on_mac.sh first")


def test_yarn_daily_totals_match_pipeline_table():
    """MapReduce daily totals from YARN equal the pipeline's daily table."""
    need(MR_DAILY)
    mr = pd.read_csv(MR_DAILY, sep="\t", header=None, names=["date", "kwh", "readings"])
    mr["Date_ISO"] = pd.to_datetime(mr["date"], format="%d/%m/%Y").dt.strftime("%Y-%m-%d")
    daily = pd.read_csv(DAILY_CSV)
    merged = mr.merge(daily[["Date_ISO", "Energy_kWh", "Reading_count"]], on="Date_ISO")
    assert len(merged) == len(daily) == len(mr)
    assert (merged["kwh"] - merged["Energy_kWh"]).abs().max() < 0.001
    assert (merged["readings"] == merged["Reading_count"]).all()


def test_yarn_hourly_profile_is_complete_and_consistent():
    """The hour-of-day job returns 24 hours whose totals agree with the daily job."""
    need(MR_HOURLY)
    need(MR_DAILY)
    hourly = pd.read_csv(MR_HOURLY, sep="\t", header=None, names=["hour", "kwh", "readings", "avg_kw", "peak_kw"])
    daily = pd.read_csv(MR_DAILY, sep="\t", header=None, names=["date", "kwh", "readings"])
    assert sorted(hourly["hour"]) == list(range(24))
    assert hourly["readings"].sum() == daily["readings"].sum()
    assert np.isclose(hourly["kwh"].sum(), daily["kwh"].sum(), atol=0.5)
    assert (hourly["peak_kw"] >= hourly["avg_kw"]).all()


def test_hive_total_energy_matches_pipeline_table():
    """Hive Query 8 (sub-metering breakdown) returns the same total energy as the daily table."""
    path = os.path.join(HIVE_DIR, "q08.csv")
    need(path)
    q8 = pd.read_csv(path)
    daily = pd.read_csv(DAILY_CSV)
    expected = daily.loc[daily["Is_valid_day"] == 1, "Energy_kWh"].sum()
    assert abs(q8["total_household_kwh"].iloc[0] - expected) < 0.1


def test_hive_raw_table_row_counts():
    """Hive Query 12 counts every reading of the raw file in HDFS."""
    path = os.path.join(HIVE_DIR, "q12.csv")
    need(path)
    q12 = pd.read_csv(path)
    assert q12["year_num"].notna().all()
    assert q12["total_readings"].sum() == 2075259
    assert q12["missing_readings"].sum() == 25979


def test_hive_hourly_profile_has_24_hours():
    """Hive Query 3 returns one row per hour with no header row leaking in as NULL."""
    path = os.path.join(HIVE_DIR, "q03.csv")
    need(path)
    q3 = pd.read_csv(path)
    assert len(q3) == 24
    assert q3["hour_of_day"].notna().all()
