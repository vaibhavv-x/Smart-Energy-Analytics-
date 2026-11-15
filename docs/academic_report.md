# Smart Energy Analytics: Household Electricity Consumption Analysis and Demand Forecasting

## Big Data Course Project Report

**Batch**: 30  
**Team**:
- **Vaibhav** — Roll No: AP23110010425
- **Saubhagya Kashyap** — Roll No: AP23110010439

**Tools**: Hadoop HDFS, Hadoop MapReduce (YARN), Apache Hive, Apache Spark (PySpark, Spark SQL, Spark MLlib), Streamlit, Matplotlib  
**Dataset**: UCI Individual Household Electric Power Consumption  
**Based on**: an open-source project released under the MIT licence (see `LICENSE`). Section 11 states which parts come from that project and which parts are ours.

---

## 1. Abstract

Smart meters record household electricity use every minute, which produces far more data than a utility bill and far more than a spreadsheet handles comfortably. This project takes four years of one-minute readings from one household (2,075,259 rows) and runs them through a Hadoop and Spark pipeline on a single-node cluster. The raw file is stored in HDFS. Two MapReduce jobs on YARN compute daily energy totals and the hour-of-day load profile. Apache Hive holds the cleaned data in ORC and Parquet tables and answers 12 analysis queries. PySpark builds leak-free time-series features, and Spark MLlib trains models that predict the next day's consumption. A Streamlit dashboard presents the results.

The main findings: demand peaks at 20:00 and is lowest at 04:00, a ratio of 4.3 to 1; weekends use 19.1% more than weekdays; December uses 2.6 times as much per day as August; and a Random Forest model predicts next-day consumption with a mean error of 3.82 kWh, against 4.50 kWh for the naive baseline.

## 2. Problem Statement

Given one-minute smart meter readings for a household:

1. The raw data has missing readings and mixed units (kW for power, Wh for sub-meters), so it cannot be summed directly.
2. Questions about patterns (when is the peak, how do seasons differ, what uses the energy) need aggregation over millions of rows.
3. Forecasting next-day demand is easy to get wrong: a model that sees same-day or future information reports accuracy it cannot achieve in use.

## 3. Objectives

1. Store the dataset in HDFS and process it with Hadoop MapReduce on YARN.
2. Build a Hive warehouse over the data and answer analysis questions in HiveQL.
3. Engineer time-series features in PySpark without data leakage.
4. Train and evaluate next-day forecasting models in Spark MLlib against a naive baseline.
5. Present the results in an interactive dashboard.

## 4. Dataset

| Property | Value |
|---|---|
| Source | UCI Machine Learning Repository (EDF R&D, France) |
| Coverage | One household in Sceaux, near Paris; 16 Dec 2006 to 26 Nov 2010 |
| Rows | 2,075,259 one-minute readings (126.8 MB) |
| Columns | Date, time, active power (kW), reactive power (kW), voltage (V), current (A), three sub-meters (Wh): kitchen, laundry, water heater and air conditioner |
| Missing | 25,979 readings (1.25%) marked `?` |

## 5. System Architecture

The cluster is a single node (Apple M1 MacBook, 8 GB RAM) running Hadoop 3.3.6, Hive 4.0.1 and PySpark 3.5.3 on Java 11. One script, `run_on_mac.sh`, installs and runs everything.

```
UCI raw file ──► HDFS /smart-energy/raw
                    │
        ┌───────────┼──────────────────────────┐
        ▼           ▼                          ▼
 MapReduce on YARN  Cleaning (pandas)   Hive external table
 - daily totals     daily + hourly      over the raw file
 - hourly profile        │
                         ▼
              HDFS /smart-energy/cleaned
                         │
           ┌─────────────┴──────────────┐
           ▼                            ▼
 Hive warehouse (ORC, Parquet)   PySpark features ──► HDFS /smart-energy/features
 12 queries on YARN                                          │
                                                             ▼
                                                  Spark MLlib models
                                                             │
                                                             ▼
                                        Streamlit dashboard and figures
```

The diagram in `docs/architecture.md` shows the same flow in more detail.

## 6. Implementation

### 6.1 Storage: HDFS

HDFS runs with one NameNode and one DataNode, replication factor 1. Everything lives under `/smart-energy`: `raw` (the dataset), `cleaned` (daily and hourly tables), `features` (Parquet), `mapreduce` (job outputs) and `hive/warehouse` (Hive tables).

### 6.2 Batch processing: MapReduce on YARN

Both jobs are Hadoop Streaming jobs written in Python. Each reads all 2,075,259 rows from HDFS and ran with two map tasks and one reduce task.

| Job | Mapper | Reducer | Output |
|---|---|---|---|
| Daily energy totals | Skips the header and `?` rows; converts each reading to energy (kW ÷ 60 = kWh); emits `date, kWh, 1` | Sums energy and counts readings per date | 1,433 rows |
| Hour-of-day load profile | Same filtering; emits `hour, kWh, kW` | Total energy, reading count, average power and peak power per hour | 24 rows |

### 6.3 Cleaning

`preprocessing/clean_data.py` reads the raw file in chunks of 250,000 rows. It drops missing readings without filling them in, converts power to energy and sub-meter Wh to kWh, and computes the energy not covered by any sub-meter. It writes an hourly table (34,168 rows) and a daily table (1,433 rows). A day counts as valid when at least 85% of its 1,440 readings are present: 1,420 days are valid. Both tables are then uploaded to HDFS.

### 6.4 Data warehouse: Apache Hive

HiveServer2 runs with an embedded Derby metastore and the MapReduce execution engine, so every aggregation runs as one or more jobs on YARN.

| Table | Storage | Source |
|---|---|---|
| `raw_household_power` | External table, text | The raw file in `/smart-energy/raw` |
| `daily_energy_consumption` | ORC, partitioned by year | Loaded from the cleaned daily table with dynamic partitioning |
| `hourly_energy_consumption` | Parquet | Loaded from the cleaned hourly table |

Twelve queries are in `hive/queries.hql`; `hive/run_hive_on_cluster.py` runs each through beeline and saves the result. Spark SQL re-runs eleven of them from HDFS as a cross-check, and the numbers agree.

### 6.5 Feature engineering: PySpark

`spark/spark_feature_pipeline.py` reads the cleaned daily table from HDFS and builds 15 features with window functions: consumption 1, 2 and 7 days earlier; the 7-day mean, 7-day standard deviation and 14-day mean of the preceding days; the previous day's average power, peak power, voltage and sub-meter totals; and day of week, weekend flag and month. Every rolling window ends on the previous day (`rowsBetween(-7, -1)`), so no feature contains information from the day being predicted. The result has 1,413 days and is written to HDFS as Parquet.

### 6.6 Forecasting: Spark MLlib

`forecasting/train_models.py` reads the features from HDFS and predicts each day's total consumption. The data is split by time, never shuffled: 989 days for training, 211 for validation and 213 for testing (19 April to 26 November 2010). Three models are compared: a naive baseline that predicts yesterday's value, Linear Regression with elastic-net regularisation, and a Random Forest with 40 trees of depth 5. The model with the lowest validation error is selected.

### 6.7 Visualization

The Streamlit dashboard (`app.py`) has six pages: overview, consumption analysis, forecasting, sustainability insights, Hadoop and Hive cluster results, and project architecture. `dashboard/generate_plots.py` renders four figures for the report with Matplotlib.

## 7. Results

### 7.1 MapReduce

- The daily totals from YARN match the cleaned daily table on all 1,433 days; the largest difference is 0.0001 kWh.
- The hour-of-day profile shows average demand lowest at 04:00 (0.44 kW) and highest at 20:00 (1.90 kW).

### 7.2 Hive analysis

| Question | Finding |
|---|---|
| Which hours are the peak? (Q3, Q4) | 20:00, 21:00 and 19:00, followed by a morning peak at 07:00 and 08:00. The busiest hour uses 4.3 times as much as the quietest. |
| Weekday or weekend? (Q6) | Weekends average 29.59 kWh per day, weekdays 24.84 kWh: 19.1% higher. |
| How do seasons differ? (Q7) | December averages 35.6 kWh per day and January 35.1; August averages 13.7 and July 16.8. |
| What uses the energy? (Q8) | Water heater and air conditioner 35.5%, laundry 7.1%, kitchen 6.2%, unmetered 51.2%. |
| Which time of day? (Q11) | Evening (18:00 to 23:59) 35.0%, morning 28.9%, afternoon 24.5%, night 11.5%. |
| Are heavy days becoming rarer? (Q10) | Days above 40 kWh fell from 12.2% of days in 2007 to 4.1% in 2010. |
| How complete is the raw data? (Q12) | Missing readings are below 1% in every year except 2010 (3.7%). |

Query times on Hive ranged from 20 to 82 seconds, because each query starts MapReduce jobs on YARN.

### 7.3 Forecasting

| Model | MAE (kWh) | RMSE (kWh) | R² | MAPE |
|---|---|---|---|---|
| Naive baseline | 4.50 | 6.42 | 0.20 | 19.2% |
| Linear Regression | 3.96 | 5.37 | 0.44 | 18.2% |
| Random Forest (selected) | 3.82 | 5.16 | 0.48 | 18.2% |

The Random Forest reduces RMSE by 19.6% and MAE by 15.1% relative to the baseline. An R² of 0.48 means the model explains about half of the day-to-day variation; the rest depends on things the data does not contain, such as weather and whether the household is at home.

### 7.4 Sustainability reading (SDG 7)

The evening band from 18:00 to 23:59 carries 35% of the household's energy, and the largest metered load is the water heater and air conditioner. Both point to the same action: moving water heating, laundry and dishwashing into the 01:00 to 05:00 valley would flatten the load curve. The dataset has no tariff information, so we do not put a money figure on it.

## 8. Testing

35 automated tests (pytest) cover the unit conversions, both mappers and reducers, leakage checks on the features, model metrics, dashboard exports and the cluster outputs. The cluster tests confirm that the YARN totals equal the cleaned table, that the hourly job returns 24 hours consistent with the daily job, and that Hive's counts on the raw table add up to 2,075,259 rows with 25,979 missing.

## 9. Limitations

1. **Scale.** 126.8 MB fits in one HDFS block. The project demonstrates the workflow of a cluster, not its scale.
2. **Single node.** Replication factor 1 and one machine, so there is no fault tolerance.
3. **Spark runs in local mode.** It reads from and writes to HDFS but does not run on YARN.
4. **Hive on MapReduce.** Queries on small tables take 20 to 82 seconds; Tez would be faster.
5. **One household, no weather data.** The findings describe one home in France, and the forecast cannot see temperature.
6. **Modest forecast accuracy.** R² is 0.48.

## 10. Conclusion and Future Work

The project runs a complete batch pipeline on Hadoop: storage in HDFS, two MapReduce jobs, a Hive warehouse with 12 queries, Spark features and MLlib models, all started by one script and checked by 35 tests. The analysis gives a consistent picture of the household: an evening peak, a strong winter effect, higher use at weekends, and a forecast that beats the naive baseline.

Next steps would be to run Spark on YARN, add weather data to the features, use Tez as the Hive engine, and repeat the analysis on a multi-household dataset large enough to need more than one HDFS block.

## 11. What comes from the base project and what is ours

**From the base project (MIT licence):** the cleaning script, the first mapper and reducer, the Hive schema and queries 1 to 8, the PySpark feature pipeline, the MLlib training script, the dashboard exports and figures, the first five dashboard pages, and 27 of the tests. In that project MapReduce ran as a local simulation on a 5,000-row sample and the HiveQL ran in Spark SQL only.

**Ours (Batch 30):**

1. `run_on_mac.sh`: single-node Hadoop and Hive on macOS in one command.
2. MapReduce on YARN over the full dataset.
3. The second MapReduce job (hour-of-day load profile).
4. The Hive warehouse on a real Hive server: the load script, the runner, and the fixes for the protobuf conflict and the header row.
5. Queries 9 to 12.
6. Spark reading from and writing to HDFS.
7. The cluster-results dashboard page and the new theme.
8. Eight tests, the macOS guides, and this report.
9. Corrections to figures in the base project's documents that did not match the data (for example, the unmetered share is 51.2%, not 58.1%).

## 12. References

1. Hébrail, G. and Bérard, A. *Individual Household Electric Power Consumption*. UCI Machine Learning Repository, 2012. https://archive.ics.uci.edu/dataset/235/individual+household+electric+power+consumption
2. Apache Hadoop documentation: HDFS architecture, YARN, Hadoop Streaming. https://hadoop.apache.org/docs/r3.3.6/
3. Apache Hive documentation: language manual, HiveServer2. https://hive.apache.org/
4. Apache Spark documentation: Spark SQL, MLlib. https://spark.apache.org/docs/3.5.3/
5. United Nations. *Sustainable Development Goal 7*. https://sdgs.un.org/goals/goal7
