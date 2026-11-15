#!/usr/bin/env python3
"""
Master Pipeline Orchestration Script
Smart Energy Consumption Analytics & Forecasting

Sequentially executes the end-to-end Big Data & Analytics pipeline:
1. Ingestion & Preprocessing (data/raw -> data/processed)
2. Hadoop MapReduce Execution & Mathematical Validation
3. HiveQL Analytical Query Execution (8 queries)
4. PySpark Feature Engineering (data/features)
5. Machine Learning Forecasting Models (Spark MLlib)
6. Power BI Star-Schema Export Generation
7. Publication Figure Rendering (screenshots/)
8. Automated Unit Test Verification (pytest)
"""

import os
import sys
import time
import subprocess

def run_step(step_num: int, title: str, cmd_args: list):
    print(f"\n{'='*75}")
    print(f"STEP {step_num}: {title.upper()}")
    print(f"{'='*75}")
    start = time.time()
    
    result = subprocess.run([sys.executable] + cmd_args, check=False)
    elapsed = time.time() - start
    
    if result.returncode != 0:
        print(f"[-] Step {step_num} FAILED in {elapsed:.2f}s with exit code {result.returncode}")
        sys.exit(result.returncode)
    else:
        print(f"[+] Step {step_num} COMPLETED SUCCESSFULLY in {elapsed:.2f}s")

def upload_cleaned_to_hdfs():
    """Copy the cleaned daily and hourly tables into HDFS so that Spark and Hive read them from there.

    Active only when SMART_ENERGY_HDFS_URI is set (for example hdfs://localhost:9000/smart-energy).
    """
    uri = os.environ.get("SMART_ENERGY_HDFS_URI", "").rstrip("/")
    if not uri:
        print("\n[i] SMART_ENERGY_HDFS_URI is not set: Spark will read the local CSV files.")
        return
    hdfs = os.environ.get("SMART_ENERGY_HDFS_BIN", "hdfs")
    print(f"\n{'='*75}")
    print("STEP 1b: UPLOAD CLEANED TABLES TO HDFS")
    print(f"{'='*75}")
    for name, local in (
        ("daily", os.path.join("data", "processed", "daily_energy_consumption.csv")),
        ("hourly", os.path.join("data", "processed", "hourly_energy_consumption.csv")),
    ):
        target = f"{uri}/cleaned/{name}"
        subprocess.run([hdfs, "dfs", "-mkdir", "-p", target], check=True)
        subprocess.run([hdfs, "dfs", "-put", "-f", local, target + "/"], check=True)
        print(f"[+] {local} -> {target}/")


def main():
    print("===========================================================================")
    print("SMART ENERGY CONSUMPTION ANALYTICS & FORECASTING")
    print("Batch 30 | Big Data Course Project Pipeline Runner")
    print("Vaibhav (AP23110010425) & Saubhagya Kashyap (AP23110010439)")
    print("===========================================================================")

    # Refuse to run on the 5,000-row sample by accident: that would overwrite the processed
    # tables with three days of data. Pass --sample to do it on purpose.
    full_dataset = os.path.join("data", "raw", "household_power_consumption.txt")
    if not os.path.exists(full_dataset) and "--sample" not in sys.argv:
        print(f"\n[-] Full dataset not found at {full_dataset}.")
        print("    Run  bash run_on_mac.sh  to download it, or pass --sample to run on the 5,000-row sample")
        print("    (this overwrites data/processed and the model step will fail on so little data).")
        sys.exit(1)

    t0 = time.time()

    # Step 1: Preprocessing
    run_step(1, "Data Cleaning and Preprocessing", ["preprocessing/clean_data.py"])

    upload_cleaned_to_hdfs()

    # Step 2: MapReduce
    run_step(2, "Hadoop MapReduce Daily Energy Aggregation & Validation", ["hadoop/run_mapreduce.py"])

    # Step 3: Hive Analytics
    run_step(3, "HiveQL Analytical Queries Execution", ["hive/run_hive_analytics.py"])

    # Step 4: Spark Feature Pipeline
    run_step(4, "PySpark Time-Series Feature Engineering", ["spark/spark_feature_pipeline.py"])

    # Step 5: Machine Learning Forecasting
    run_step(5, "Spark MLlib Model Training & Evaluation", ["forecasting/train_models.py"])

    # Step 6: Power BI Exports
    run_step(6, "Power BI Star-Schema CSV Export Generation", ["dashboard/generate_dashboard_exports.py"])

    # Step 7: Plot Generation
    run_step(7, "Publication Figures and Visualizations Rendering", ["dashboard/generate_plots.py"])

    # Step 8: Pytest Verification
    print(f"\n{'='*75}")
    print("STEP 8: AUTOMATED UNIT TEST SUITE (PYTEST)")
    print(f"{'='*75}")
    res_test = subprocess.run([sys.executable, "-m", "pytest", "tests/", "-v"], check=False)
    if res_test.returncode != 0:
        print("[-] Unit tests failed!")
        sys.exit(res_test.returncode)

    total_time = time.time() - t0
    print("\n" + "="*75)
    print(f"[SUCCESS] COMPLETE PIPELINE EXECUTED AND VERIFIED IN {total_time:.2f}s!")
    print("="*75)

if __name__ == "__main__":
    main()
