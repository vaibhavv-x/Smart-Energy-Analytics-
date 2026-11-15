"""
Automated tests: outputs of the jobs that ran on the Hadoop cluster (MapReduce on
YARN and Apache Hive) and of the R scripts. Each test is skipped when its input
file does not exist yet, i.e. before `bash run_on_mac.sh` has been run.
"""

import csv
import os

import pytest

MR_DAILY = os.path.join("hadoop", "mapreduce_yarn_daily_output.txt")
MR_HOURLY = os.path.join("hadoop", "mapreduce_yarn_hourly_output.txt")
HIVE_DIR = os.path.join("hive", "cluster_results")
R_DIR = os.path.join("r", "output")
GRAPHS_DIR = "graphs"


def read_csv(path):
    if not os.path.exists(path):
        pytest.skip(f"{path} not found; run bash run_on_mac.sh first")
    with open(path, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def read_tsv(path):
    if not os.path.exists(path):
        pytest.skip(f"{path} not found; run bash run_on_mac.sh first")
    with open(path, encoding="utf-8") as f:
        return [line.rstrip("\n").split("\t") for line in f if line.strip()]


def iso(date_dmy):
    day, month, year = date_dmy.split("/")
    return f"{year}-{int(month):02d}-{int(day):02d}"


def test_mapreduce_daily_totals_match_hive_daily_series():
    """The MapReduce job and Hive compute the same daily energy from the same raw file."""
    mr = {iso(r[0]): (float(r[1]), int(r[2])) for r in read_tsv(MR_DAILY)}
    hive = read_csv(os.path.join(HIVE_DIR, "q01.csv"))   # valid days only
    assert len(mr) == 1433 and len(hive) == 1420
    for row in hive:
        kwh, readings = mr[row["consumption_date"]]
        assert abs(kwh - float(row["daily_energy_kwh"])) < 0.001
        assert readings == int(row["reading_count"])


def test_mapreduce_hourly_profile_is_complete_and_consistent():
    """The hour-of-day job returns 24 hours whose totals agree with the daily job."""
    hourly = read_tsv(MR_HOURLY)
    daily = read_tsv(MR_DAILY)
    assert sorted(int(r[0]) for r in hourly) == list(range(24))
    assert sum(int(r[2]) for r in hourly) == sum(int(r[2]) for r in daily) == 2049280
    assert abs(sum(float(r[1]) for r in hourly) - sum(float(r[1]) for r in daily)) < 0.5
    assert all(float(r[4]) >= float(r[3]) for r in hourly)


def test_hive_and_mapreduce_agree_on_hourly_profile():
    """Hive query 3 and MapReduce job 2 give the same average power per hour."""
    mr = {int(r[0]): float(r[3]) for r in read_tsv(MR_HOURLY)}
    hive = read_csv(os.path.join(HIVE_DIR, "q03.csv"))
    assert len(hive) == 24
    for row in hive:
        assert abs(mr[int(row["hour_of_day"])] - float(row["avg_power_kw"])) < 0.01


def test_hive_raw_table_row_counts():
    """Hive query 12 counts every reading of the raw file in HDFS."""
    rows = read_csv(os.path.join(HIVE_DIR, "q12.csv"))
    assert all(r["year_num"] not in ("", "NULL") for r in rows)
    assert sum(int(r["total_readings"]) for r in rows) == 2075259
    assert sum(int(r["missing_readings"]) for r in rows) == 25979


def test_hive_submetering_shares_add_up():
    """Hive query 8: the four shares of energy add up to 100%."""
    row = read_csv(os.path.join(HIVE_DIR, "q08.csv"))[0]
    shares = [float(row[c]) for c in ("kitchen_percentage", "laundry_percentage",
                                      "climate_water_percentage", "remainder_percentage")]
    assert abs(sum(shares) - 100.0) < 0.05


def test_hive_features_have_no_leakage():
    """Every lag feature equals an earlier day's value, and rolling means use only earlier days."""
    rows = read_csv(os.path.join(HIVE_DIR, "daily_features.csv"))
    assert len(rows) == 1413
    energy = [float(r["energy_kwh"]) for r in rows]
    dates = [r["consumption_date"] for r in rows]
    assert dates == sorted(dates)
    for i in range(14, len(rows)):
        assert abs(float(rows[i]["lag_1_energy_kwh"]) - energy[i - 1]) < 1e-6
        assert abs(float(rows[i]["lag_7_energy_kwh"]) - energy[i - 7]) < 1e-6
        assert abs(float(rows[i]["rolling_mean_7_kwh"]) - sum(energy[i - 7:i]) / 7) < 1e-6
        assert abs(float(rows[i]["rolling_mean_14_kwh"]) - sum(energy[i - 14:i]) / 14) < 1e-6
    assert all(v not in ("", "NULL") for r in rows for v in r.values())


def test_r_models_beat_the_naive_baseline():
    """Both R models have a lower test error than the naive baseline, and one model is selected."""
    rows = {r["model"]: r for r in read_csv(os.path.join(R_DIR, "model_metrics.csv"))}
    base = float(rows["Naive_Baseline"]["test_rmse"])
    assert float(rows["Linear_Regression"]["test_rmse"]) < base
    assert float(rows["Random_Forest"]["test_rmse"]) < base
    assert sum(r["selected"] == "yes" for r in rows.values()) == 1


def test_r_predictions_cover_the_test_period():
    """The prediction file has one row per test day, in date order, with positive predictions."""
    rows = read_csv(os.path.join(R_DIR, "test_predictions.csv"))
    assert len(rows) == 213
    dates = [r["date"] for r in rows]
    assert dates == sorted(dates) and dates[0] == "2010-04-19" and dates[-1] == "2010-11-26"
    assert all(float(r["random_forest_kwh"]) > 0 and float(r["linear_regression_kwh"]) > 0 for r in rows)


def test_r_graphs_exist():
    """The R visualization script produced all twelve graphs."""
    if not os.path.isdir(GRAPHS_DIR):
        pytest.skip("graphs/ not found; run bash run_on_mac.sh first")
    pngs = [f for f in os.listdir(GRAPHS_DIR) if f.endswith(".png")]
    assert len(pngs) == 12
    assert all(os.path.getsize(os.path.join(GRAPHS_DIR, f)) > 10000 for f in pngs)
