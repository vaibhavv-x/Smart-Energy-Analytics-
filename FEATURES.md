# Features: what this project contains

Smart Energy Analytics: household electricity consumption analysis and next-day demand forecasting.
Batch 30: Vaibhav (AP23110010425) and Saubhagya Kashyap (AP23110010439).

This file lists everything that exists in the folder today. For what still has to be done, see [TODO.md](TODO.md).

**Base repo:** [Praveensagar07/Smart-Energy-Analytics-Forecasting](https://github.com/Praveensagar07/Smart-Energy-Analytics-Forecasting), MIT licence. Keep the `LICENSE` file and the credit lines. The section "What we added" below lists our own work.

## Dataset

- **Source:** UCI Machine Learning Repository, *Individual Household Electric Power Consumption* (EDF R&D). One house in Sceaux, near Paris.
- **Size:** 2,075,259 one-minute readings, 16 Dec 2006 to 26 Nov 2010.
- **Columns:** date, time, active power (kW), reactive power, voltage, current, and three sub-meters (kitchen, laundry, water heater and air conditioning).
- **Missing data:** 25,979 readings (1.25%) are marked `?`. They are dropped, never filled in.
- **Where the files are:**

| File | Location | Size |
|---|---|---|
| Full dataset | `data/raw/household_power_consumption.txt` | 126.8 MB, 2,075,259 rows |
| Same file in HDFS | `hdfs://localhost:9000/smart-energy/raw/household_power_consumption.txt` | 1 block, replication 1 |
| Spare copy | `~/bigdata/dataset/household_power_consumption.txt` | 126.8 MB |
| 5,000-row sample | `data/raw/sample_household_power_consumption.txt` | 0.3 MB |

The full file is excluded from git (`.gitignore`), so a teammate who clones the project gets it by running `run_on_mac.sh`, which downloads it from UCI.

## Pipeline at a glance

| # | Stage | Tool | Script | Output |
|---|---|---|---|---|
| 1 | Storage | Hadoop HDFS (single node) | `run_on_mac.sh` | `/smart-energy/...` in HDFS |
| 2 | Daily totals | Hadoop MapReduce on YARN | `hadoop/mapper.py`, `reducer.py` | `hadoop/mapreduce_yarn_daily_output.txt` |
| 3 | Hour-of-day profile | Hadoop MapReduce on YARN | `hadoop/mapper_hourly.py`, `reducer_hourly.py` | `hadoop/mapreduce_yarn_hourly_output.txt` |
| 4 | Cleaning and aggregation | Python (pandas, in chunks) | `preprocessing/clean_data.py` | `data/processed/`, then HDFS `/smart-energy/cleaned` |
| 5 | Data warehouse | Apache Hive 4.0.1 (HiveServer2) | `hive/*.hql`, `hive/run_hive_on_cluster.py` | `hive/cluster_results/` |
| 6 | SQL cross-check | Spark SQL, reading HDFS | `hive/run_hive_analytics.py` | `hive/query_results/` |
| 7 | Feature engineering | PySpark, reading HDFS | `spark/spark_feature_pipeline.py` | `data/features/`, HDFS `/smart-energy/features` |
| 8 | Forecasting | Spark MLlib, reading HDFS | `forecasting/train_models.py` | `forecasting/` |
| 9 | Dashboard data and figures | pandas, Matplotlib | `dashboard/*.py` | `dashboard/power_bi_exports/`, `screenshots/` |
| 10 | Interactive dashboard | Streamlit with Plotly | `app.py` | http://localhost:8501 |
| 11 | Tests | pytest | `tests/` | 35 tests |

`bash run_on_mac.sh` installs everything and runs all of it. See [docs/installation.md](docs/installation.md) and [docs/execution.md](docs/execution.md).

## What is in HDFS

| Path | Contents |
|---|---|
| `/smart-energy/raw` | The raw dataset (126.8 MB) |
| `/smart-energy/cleaned/daily`, `/hourly` | Cleaned daily and hourly tables (CSV) |
| `/smart-energy/features/daily_energy_features` | Feature table written by Spark (Parquet) |
| `/smart-energy/mapreduce/daily_consumption` | Output of MapReduce job 1 |
| `/smart-energy/mapreduce/hourly_profile` | Output of MapReduce job 2 |
| `/smart-energy/hive/warehouse/smart_energy_db.db` | Hive tables: daily (ORC, one folder per year) and hourly (Parquet) |

## Feature list

### 1. Data cleaning (`preprocessing/clean_data.py`)

- Reads the raw file in chunks of 250,000 rows so it fits in 8 GB of RAM.
- Treats `?` as missing and drops those readings.
- Converts power to energy: kW ÷ 60 = kWh per one-minute reading.
- Converts the three sub-meters from Wh to kWh and computes the unmetered remainder.
- Builds an hourly table (34,168 rows) and a daily table (1,433 rows).
- Flags valid days (at least 85% of readings present): 1,420 valid, 13 incomplete.
- Writes `cleaning_summary.json` with the row counts and totals.
- **Catch:** if the full dataset is missing it silently falls back to the 5,000-row sample and overwrites the processed tables.

### 2. HDFS and YARN (`run_on_mac.sh`)

- Single-node Hadoop 3.3.6: NameNode, DataNode, ResourceManager, NodeManager; replication factor 1.
- The script writes `core-site.xml`, `hdfs-site.xml`, `mapred-site.xml` and `yarn-site.xml`, formats HDFS on the first run and starts the daemons without ssh.
- HDFS, YARN, HiveServer2 and the dashboard listen on this machine only (127.0.0.1), because none of them has a login. The MapReduce shuffle port (13562) is the one exception while the cluster is running.

### 3. MapReduce (`hadoop/`)

Two Hadoop Streaming jobs, each run on YARN over all 2,075,259 rows (2 map tasks, 1 reduce task):

| Job | Mapper emits | Reducer returns | Result |
|---|---|---|---|
| Daily energy totals | `date, kWh, 1` | total kWh and reading count per date | 1,433 rows; matches the pipeline table within 0.0001 kWh on every day |
| Hour-of-day load profile | `hour, kWh, kW` | total kWh, readings, average kW and peak kW per hour | 24 rows; lowest demand at 04:00 (0.44 kW), highest at 20:00 (1.90 kW) |

- Both mappers skip the header, `?` values and malformed rows.
- `hadoop/run_mapreduce.py` is a local check of job 1 on the sample (no Hadoop needed).
- Job logs from YARN are saved as `hadoop/mapreduce_yarn_job_log.txt` and `hadoop/mapreduce_yarn_hourly_job_log.txt`.

### 4. Apache Hive (`hive/`)

- Hive 4.0.1 with HiveServer2 (JDBC on port 10000, web page on 10002), an embedded Derby metastore, and the MapReduce engine on YARN.
- `schema.hql`: database `smart_energy_db`; an external table over the raw file; a daily table stored as ORC and partitioned by year; an hourly table stored as Parquet.
- `load_cleaned_tables.hql`: staging tables over the cleaned CSV files in HDFS, then `INSERT OVERWRITE` with dynamic partitioning.
- `queries.hql`: 12 queries. `run_hive_on_cluster.py` runs each through beeline and saves `hive/cluster_results/q01.csv` to `q12.csv` plus `hive_cluster_report.md` with timings.

| Query | Question it answers | Rows | Seconds on Hive |
|---|---|---|---|
| Q1 | Daily consumption over time | 1,420 | 21 |
| Q2 | Monthly totals and averages | 48 | 42 |
| Q3 | Average consumption for each hour of the day | 24 | 43 |
| Q4 | Top 5 peak hours | 5 | 42 |
| Q5 | Top 10 highest-consumption dates | 10 | 21 |
| Q6 | Weekday against weekend | 2 | 20 |
| Q7 | Seasonal pattern by calendar month | 12 | 41 |
| Q8 | Share of kitchen, laundry, climate and unmetered use | 1 | 22 |
| Q9 (ours) | Year-on-year change in each month's consumption | 36 | 82 |
| Q10 (ours) | Share of days above 40 kWh per year | 5 | 40 |
| Q11 (ours) | Consumption by time-of-day band | 4 | 60 |
| Q12 (ours) | Valid and missing readings per year, on the raw 2-million-row table | 5 | 45 |

- `run_hive_analytics.py` runs Q1 to Q11 in Spark SQL, reading from HDFS, as a cross-check. The two engines return the same numbers (for example, 37,172.66 kWh of valid-day energy).

### 5. PySpark feature engineering (`spark/spark_feature_pipeline.py`)

- Reads the cleaned daily table from HDFS.
- Lags of daily energy: 1, 2 and 7 days.
- Rolling 7-day mean, 7-day standard deviation and 14-day mean, using only earlier days (no leakage).
- Yesterday's average power, peak power, voltage and three sub-meter totals.
- Calendar features: day of week, weekend flag, month.
- Output: 1,413 days with 15 model features, saved locally as CSV and to HDFS as Parquet.

### 6. Forecasting with Spark MLlib (`forecasting/train_models.py`)

- Reads the feature table from HDFS and predicts the next day's total consumption in kWh.
- Split by time, never shuffled: 989 training days, 211 validation, 213 test.
- Three models: naive baseline (tomorrow = today), Linear Regression (elastic net), Random Forest (40 trees, depth 5).

Test-set results from our own run on this Mac (15 Nov 2026):

| Model | MAE (kWh) | RMSE (kWh) | R² | MAPE |
|---|---|---|---|---|
| Naive baseline | 4.50 | 6.42 | 0.20 | 19.2% |
| Linear Regression | 3.96 | 5.37 | 0.44 | 18.2% |
| Random Forest (selected) | 3.82 | 5.16 | 0.48 | 18.2% |

Both models beat the baseline, which is the honest claim to make. An R² of 0.48 is modest.

### 7. Dashboard exports and figures (`dashboard/`)

- Five star-schema CSVs: `dim_calendar`, `fact_daily_energy`, `fact_hourly_energy`, `fact_forecast_comparison`, `dim_model_performance`.
- Adds an estimated cost at 0.20 EUR per kWh and an anomaly-day flag.
- These tables can be loaded into Power BI or Tableau; no such report has been built.
- `generate_plots.py` renders four PNG figures into `screenshots/`.

### 8. Streamlit dashboard (`app.py`)

Six pages, with a date-range filter and tariff slider in the sidebar:

1. Energy overview and KPIs
2. Deep-dive consumption analysis
3. Machine learning forecasting
4. Sustainability and SDG 7 insights
5. Hadoop and Hive cluster results (ours): MapReduce totals against the pipeline table, the hour-of-day chart, and a picker for the 12 Hive results
6. Project details and big data architecture

It reads the saved CSV and JSON outputs, so it works even when Hadoop is stopped.

### 9. Tests (`tests/`)

35 tests, all passing: preprocessing (6), MapReduce job 1 (6), MapReduce job 2 (3), features (5), models (3), dashboard exports (4), Streamlit data (3), cluster outputs from YARN and Hive (5). The cluster tests are skipped on a machine where `run_on_mac.sh` has not been run.

### 10. Documentation (`docs/`)

| File | Contents |
|---|---|
| `installation.md` | macOS setup, commands, troubleshooting (rewritten by us) |
| `execution.md` | What each stage does and a viva demonstration sequence (rewritten by us) |
| `architecture.md` | Architecture diagram and components (diagram redrawn by us) |
| `results.md` | Results; section 5 holds our cluster run |
| `limitations.md` | Dataset, cluster and model limits |
| `viva_questions.md` | 30 questions with answers; Q24 to Q30 cover our cluster setup |
| `methodology.md` | Formulas and leakage rules (base project) |
| `academic_report.md` | Our project report; section 11 separates the base project's work from ours |

### 11. Browser screenshots (`screenshots/demo/`)

17 images taken on 15 Nov 2026: HDFS overview, DataNode, the `/smart-energy` tree, the raw dataset, cleaned tables, MapReduce outputs, the Hive warehouse partitions, the Parquet feature table, YARN applications and nodes, the HiveServer2 page, and the six dashboard pages.

### 12. Mac setup script (`run_on_mac.sh`)

No sudo and no Homebrew; everything goes into `~/bigdata` (about 3.5 GB).

| Command | What it does |
|---|---|
| `bash run_on_mac.sh` | Installs Java 11, Hadoop 3.3.6, Hive 4.0.1, the dataset and PySpark 3.5.3; starts HDFS, YARN and HiveServer2; runs both MapReduce jobs, the pipeline and the 12 Hive queries |
| `bash run_on_mac.sh hive` | Runs only the Hive stage again |
| `bash run_on_mac.sh status` | Shows running daemons and HDFS contents |
| `bash run_on_mac.sh stop` | Stops HiveServer2 and Hadoop |
| `bash run_on_mac.sh dashboard` | Opens the Streamlit dashboard |

## What we added to the base project

1. `run_on_mac.sh`: single-node Hadoop and Hive on macOS in one command.
2. MapReduce on YARN over the full dataset (the base project only simulated it locally on 5,000 rows).
3. A second MapReduce job: the hour-of-day load profile.
4. A real Hive warehouse with ORC and Parquet tables, a load script, and a runner (the base project ran its HiveQL in Spark SQL only).
5. Four new queries (Q9 to Q12), one of them on the raw 2-million-row table.
6. Spark reading its inputs from HDFS and writing the feature table to HDFS.
7. A new dashboard page for the cluster results, and a new colour theme.
8. Eight new tests.
9. macOS installation and execution guides, a redrawn architecture diagram, seven new viva answers, and the project report.
10. Corrections to figures in the base project's documents and dashboard that did not match the data (unmetered share 51.2%, not 58.1%; evening peak 1.71 kW, not 2.12 kW; anomaly threshold 46.2 kWh, not 48.2 kWh), and removal of an unsupported "€280 to €420 saving" claim.

## What we can and cannot claim

| Tool | Status | What to say |
|---|---|---|
| Hadoop HDFS | Real | Single-node cluster; raw data, cleaned tables, features and the Hive warehouse are stored in HDFS |
| Hadoop MapReduce, YARN | Real | Two Hadoop Streaming jobs on YARN over 2.07 million rows |
| Apache Hive | Real | Hive 4.0.1, HiveServer2, ORC and Parquet tables, 12 queries run as MapReduce jobs on YARN |
| Apache Spark (PySpark, Spark SQL, MLlib) | Real, local mode | Reads from and writes to HDFS; the Spark session runs locally, not on YARN |
| Streamlit, Matplotlib | Real | Working six-page dashboard and four figures |
| Power BI | **Not built** | Only export CSVs and a design document; Power BI Desktop does not run on a Mac |
| Pig, Sqoop, HBase, Kafka | Not present | Do not list them |
