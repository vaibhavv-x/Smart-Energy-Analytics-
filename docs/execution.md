# Pipeline Execution & Demonstration Guide

## Smart Energy Consumption Analytics & Forecasting
**Batch**: 30  
**Team**: Vaibhav (AP23110010425) & Saubhagya Kashyap (AP23110010439)

---

## 1. Run everything

```bash
bash run_on_mac.sh
```

See [installation.md](installation.md) for what each stage installs. The sections below describe what each stage computes and how to run it alone. For the stand-alone commands, first set the environment as in section 4 of the installation guide.

## 2. Stages

### Stage A: dataset into HDFS

```bash
hdfs dfs -mkdir -p /smart-energy/raw
hdfs dfs -put -f data/raw/household_power_consumption.txt /smart-energy/raw/
```

### Stage B: MapReduce on YARN (two Hadoop Streaming jobs)

| Job | Scripts | Output in HDFS | Local copy |
|---|---|---|---|
| Daily energy totals | `hadoop/mapper.py`, `hadoop/reducer.py` | `/smart-energy/mapreduce/daily_consumption` | `hadoop/mapreduce_yarn_daily_output.txt` (1,433 rows) |
| Hour-of-day load profile | `hadoop/mapper_hourly.py`, `hadoop/reducer_hourly.py` | `/smart-energy/mapreduce/hourly_profile` | `hadoop/mapreduce_yarn_hourly_output.txt` (24 rows) |

Both read all 2,075,259 rows from HDFS. To test a mapper and reducer without Hadoop:

```bash
python3 hadoop/mapper_hourly.py < data/raw/household_power_consumption.txt | sort -k1,1 | python3 hadoop/reducer_hourly.py
```

### Stage C: analysis pipeline

```bash
export SMART_ENERGY_HDFS_URI=hdfs://localhost:9000/smart-energy
export SMART_ENERGY_HDFS_BIN=$HADOOP_HOME/bin/hdfs
~/bigdata/venv/bin/python scripts/run_pipeline.py
```

| Step | Script | What it does | Output |
|---|---|---|---|
| 1 | `preprocessing/clean_data.py` | Cleans the raw file; builds daily (1,433 rows) and hourly (34,168 rows) tables | `data/processed/` |
| 1b | (in `run_pipeline.py`) | Uploads both tables to HDFS | `/smart-energy/cleaned/daily`, `/hourly` |
| 2 | `hadoop/run_mapreduce.py` | Local mapper and reducer check on the 5,000-row sample | `hadoop/mapreduce_daily_output.txt` |
| 3 | `hive/run_hive_analytics.py` | 11 HiveQL queries in Spark SQL, reading from HDFS | `hive/query_results/`, `hive/hive_execution_report.md` |
| 4 | `spark/spark_feature_pipeline.py` | 15 leak-free features, reading from HDFS | `data/features/`, `/smart-energy/features` (Parquet) |
| 5 | `forecasting/train_models.py` | Naive baseline, Linear Regression, Random Forest; reads features from HDFS | `forecasting/` |
| 6 | `dashboard/generate_dashboard_exports.py` | Five star-schema CSV tables | `dashboard/power_bi_exports/` |
| 7 | `dashboard/generate_plots.py` | Four report figures | `screenshots/` |
| 8 | `pytest tests/` | 35 automated tests | terminal |

Without `SMART_ENERGY_HDFS_URI`, steps 3 to 5 read the local CSV files and step 1b is skipped.

### Stage D: Apache Hive

```bash
bash run_on_mac.sh hive
```

This starts HiveServer2 and runs `hive/run_hive_on_cluster.py`, which executes:

1. `hive/schema.hql`: database `smart_energy_db`, an external table over the raw file, a daily ORC table partitioned by year, an hourly Parquet table.
2. `hive/load_cleaned_tables.hql`: staging tables over the cleaned CSV files in HDFS and two `INSERT OVERWRITE` statements (dynamic partitioning).
3. `hive/queries.hql`: 12 queries, each run separately through beeline.

Results are saved as `hive/cluster_results/q01.csv` to `q12.csv`, with timings in `hive/hive_cluster_report.md`. Every aggregation runs as one or more MapReduce jobs on YARN, so the stage takes about 9 minutes.

### Stage E: dashboard

```bash
bash run_on_mac.sh dashboard
```

## 3. Tests

```bash
~/bigdata/venv/bin/python -m pytest tests -v
```

## 4. Demonstration sequence for the viva

1. `bash run_on_mac.sh status`: show the four Hadoop daemons and the files in HDFS.
2. http://localhost:9870 → Utilities → Browse the file system → `/smart-energy`: the raw file, cleaned tables, features, MapReduce outputs and Hive warehouse.
3. http://localhost:8088: the finished MapReduce jobs and the Hive query jobs.
4. Open `hadoop/mapper_hourly.py` and `hadoop/reducer_hourly.py`, then `hadoop/mapreduce_yarn_hourly_output.txt`.
5. Run one Hive query live:
   ```bash
   beeline -u jdbc:hive2://localhost:10000/smart_energy_db -n $USER -e "SELECT year_num, COUNT(*) FROM daily_energy_consumption GROUP BY year_num;"
   ```
6. Open `hive/hive_cluster_report.md` for all 12 results.
7. Open the dashboard; the "Hadoop & Hive Cluster Results" page shows the cluster outputs, and the forecasting page shows the model against the naive baseline.
8. `~/bigdata/venv/bin/python -m pytest tests -q`: 35 tests pass.
