# System Architecture Document

## Smart Energy Consumption Analytics & Forecasting
**Batch**: 30  
**Subject**: Big Data Analytics (BDA)  
**Team**: Vaibhav (AP23110010425) & Saubhagya Kashyap (AP23110010439)  
**Sustainable Development Goal**: SDG 7 — Affordable and Clean Energy (Level 3)

---

## 1. Architectural Overview

The system implements a scalable, lambda-inspired Big Data analytics architecture tailored for high-frequency electrical smart meter streams. The pipeline takes raw 1-minute smart meter telemetry (over 2 million observations), cleans and normalizes physical units, validates data completeness, performs distributed batch aggregations via Hadoop MapReduce and HiveQL, builds leak-free historical time-series features in Apache Spark, trains machine learning forecasting models via Spark MLlib, and serves the results through a Streamlit dashboard and Matplotlib figures. Star-schema CSV tables are also exported for Power BI or Tableau.

```mermaid
flowchart TD
    RAW["UCI raw file<br/>2,075,259 one-minute readings"] --> HDFSRAW["HDFS /smart-energy/raw"]

    subgraph Batch["Hadoop MapReduce on YARN"]
        MR1["Job 1: daily energy totals<br/>mapper.py, reducer.py"]
        MR2["Job 2: hour-of-day load profile<br/>mapper_hourly.py, reducer_hourly.py"]
    end
    HDFSRAW --> MR1
    HDFSRAW --> MR2

    RAW --> CLEAN["Cleaning and aggregation<br/>clean_data.py"]
    CLEAN --> HDFSCLEAN["HDFS /smart-energy/cleaned<br/>daily and hourly tables"]

    subgraph Warehouse["Apache Hive (HiveServer2, MapReduce engine)"]
        HRAW["External table over the raw file"]
        HTAB["daily table: ORC, partitioned by year<br/>hourly table: Parquet"]
        HQ["12 HiveQL queries"]
        HRAW --> HQ
        HTAB --> HQ
    end
    HDFSRAW --> HRAW
    HDFSCLEAN --> HTAB

    subgraph SparkML["Apache Spark"]
        SQL["Spark SQL: same analysis, cross-check"]
        FEAT["PySpark window features<br/>lags and preceding rolling statistics"]
        HDFSFEAT["HDFS /smart-energy/features (Parquet)"]
        ML["Spark MLlib<br/>naive baseline, Linear Regression, Random Forest"]
        FEAT --> HDFSFEAT --> ML
    end
    HDFSCLEAN --> SQL
    HDFSCLEAN --> FEAT

    MR1 --> DASH["Streamlit dashboard and Matplotlib figures"]
    MR2 --> DASH
    HQ --> DASH
    ML --> DASH
```

---

## 2. Component Breakdown

### A. Raw Ingestion Layer
- **Source**: UCI Individual Household Electric Power Consumption dataset.
- **Physical Sampling**: 1-minute temporal resolution between December 16, 2006 and November 26, 2010 (1,442 calendar days).
- **Attributes Ingested**: Active Power (kW), Reactive Power (kW), Voltage (V), Intensity (A), Sub-metering 1 (Kitchen Wh), Sub-metering 2 (Laundry Wh), Sub-metering 3 (Climate control Wh).
- **Missing Value Handling**: Exact `?` detection; omitting corrupted records without silent or synthetic interpolation.

### B. Distributed Storage Layer (HDFS)
- **Directory Hierarchy**:
  - `/smart-energy/raw`: Staging directory for immutable source files.
  - `/smart-energy/cleaned`: Intermediate partitioned daily and hourly data.
  - `/smart-energy/mapreduce`: Output sinks for MapReduce partition files (`part-00000`).
  - `/smart-energy/hive/warehouse`: Hive metastore database storage for managed ORC/Parquet tables.

### C. Processing & Querying Engines (MapReduce & Hive)
- **Hadoop MapReduce (Streaming)**:
  - `mapper.py`: Streams individual line records, performs unit transformation $\text{kWh} = \text{kW} \times (1/60)$, and emits key-value pairs `Date \t Interval_Energy_kWh \t 1`.
  - `reducer.py`: Consolidates keys across the shuffle/sort barrier, aggregating daily energy consumption and validating total daily sampling counts.
- **Second MapReduce job**: `mapper_hourly.py` and `reducer_hourly.py` compute total energy, average power and peak power for each hour of the day.
- **Apache Hive (HiveServer2)**: an external table over the raw file, a daily ORC table partitioned by year and an hourly Parquet table, loaded from HDFS with dynamic partitioning. All 12 queries run as MapReduce jobs on YARN.
- **Spark SQL cross-check**:
  - Executes the HiveQL analysis (11 queries on the cleaned tables) measuring diurnal variation, historical maximum dates, weekday vs. weekend behavioral shifts, seasonal monthly trends, and sub-metering end-use distributions.

### D. PySpark Feature Engineering & MLlib Modeling
- **Feature Engineering**:
  - Lags: 1-day, 2-day, and 7-day lagged consumption.
  - Rolling windows: strictly preceding 7-day and 14-day rolling averages and standard deviations (`rowsBetween(-7, -1)`).
- **Time-Series Partitioning**:
  - Strict chronological order (Train: 2006-12 to 2009-09; Validation: 2009-09 to 2010-04; Test: 2010-04 to 2010-11). Random cross-validation is strictly forbidden to preserve causal temporal ordering.
- **MLlib Algorithms**:
  - Naive Persistence: Predicts tomorrow's energy as yesterday's consumption.
  - Linear Regression: ElasticNet regularized linear predictor.
  - Random Forest Regressor: Non-linear decision tree ensemble trained with 40 trees.

### E. Serving & Visualization Layer (Streamlit, Matplotlib, Power BI exports)
- **Dimensional Modeling**: Star schema with `dim_calendar` establishing 1-to-many relationships with daily, hourly, and forecast fact tables.
- **Sustainability & SDG 7 Reporting**: Pinpoints peak demand windows (18:00–21:00) vs. off-peak valleys (01:00–05:00) to formulate data-supported demand-side load shifting recommendations.
