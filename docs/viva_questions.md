# Comprehensive Academic Viva Questions & Technical Answers

## Smart Energy Consumption Analytics & Forecasting
**Subject**: Big Data Analytics (BDA)  
**Batch**: 30  
**Team Members**: Vaibhav (AP23110010425) & Saubhagya Kashyap (AP23110010439)

---

### 1. Big Data Architecture & Core Syllabus (Hadoop, HDFS, MapReduce, Hive)

#### Q1. What is the fundamental architecture of the Hadoop Distributed File System (HDFS)?
**Answer**: HDFS employs a master/slave architecture consisting of a single **NameNode** (master daemon managing directory namespace, file metadata, and block locations) and multiple **DataNodes** (worker daemons managing actual 128 MB data storage blocks). HDFS ensures fault tolerance through automatic triplication of blocks across separate physical rack topologies.

#### Q2. Why is Hadoop MapReduce suitable for aggregating high-frequency smart meter readings?
**Answer**: MapReduce employs the "data locality" principle—moving compute logic to data rather than shifting massive dataset blocks across the network. The mapper converts raw minute-level electrical power readings into kilowatt-hour interval slices in parallel across partitions, while the shuffle/sort barrier groups records by date key, allowing reducers to perform deterministic linear summations in $O(N)$ time.

#### Q3. How does Hadoop Streaming work in your project implementation?
**Answer**: Hadoop Streaming utilizes standard UNIX input/output streams (`stdin` / `stdout`). The Hadoop Java wrapper executes our Python mapper script, feeds lines of text via `stdin`, receives tab-separated key-value pairs (`Date \t Energy_kWh \t 1`) from `stdout`, sorts them by key in the MapReduce framework, and streams them into our Python reducer script to compute daily totals.

#### Q4. What is Hive, and how does it translate SQL into Big Data execution plans?
**Answer**: Apache Hive is a distributed data warehouse built on top of Hadoop that provides SQL-like querying (HiveQL). The Hive compiler parses SQL queries, generates an Abstract Syntax Tree (AST), validates schemas against the **Hive Metastore**, optimizes the physical execution graph using cost-based optimizers (Calcite), and generates MapReduce, Tez, or Spark jobs.

#### Q5. What is the difference between an External Table and an Internal (Managed) Table in Hive?
**Answer**: In a **Managed Table**, Hive controls both metadata and underlying physical data files; dropping the table deletes both metadata and files on HDFS. In an **External Table** (which we used for raw staging `/smart-energy/raw`), Hive manages only schema metadata; dropping the external table preserves the original underlying dataset files on HDFS.

---

### 2. Apache Spark & PySpark Analytics

#### Q6. Why is Apache Spark substantially faster than traditional MapReduce for feature engineering?
**Answer**: Spark executes computations **in-memory** using Resilient Distributed Datasets (RDDs) and Catalyst DataFrames, avoiding costly intermediate disk I/O between iterative stages. MapReduce forces a full write of shuffle outputs to local disk and HDFS between stages, creating significant disk serialization bottlenecks.

#### Q7. What is the role of Spark's Catalyst Optimizer and Tungsten Execution Engine?
**Answer**: The **Catalyst Optimizer** automatically optimizes relational query trees through rule-based and cost-based optimizations (predicate pushdown, constant folding, projection pruning). The **Tungsten Engine** provides off-heap memory management and whole-stage code generation, compiling complex DataFrame query pipelines into optimized JVM bytecode to bypass Java object overhead.

#### Q8. Where does Spark read its data from in this project, and where does it run?
**Answer**: Spark reads the cleaned daily and hourly tables from HDFS (`hdfs://localhost:9000/smart-energy/cleaned`) and writes the feature table back to HDFS as Parquet (`/smart-energy/features`); the MLlib training job reads that Parquet file. The Spark session itself runs in local mode on the same machine, not on YARN, because the cleaned tables are small (1,433 daily rows and 34,168 hourly rows).

---

### 3. Machine Learning, Time-Series & Leakage Prevention

#### Q9. What is Data Leakage in time-series forecasting, and how was it prevented in your pipeline?
**Answer**: Data leakage occurs when predictor features inadvertently expose information from the target timestamp $t$ or future timestamps ($t+k$). We prevented leakage by computing rolling statistical windows strictly backwards over preceding rows (`rowsBetween(-W, -1)`) and using lagged predictors ($\text{Lag}_1 = y_{t-1}, \text{Lag}_7 = y_{t-7}$), strictly excluding the current day's consumption $y_t$ from its own feature vector.

#### Q10. Why is random K-Fold Cross-Validation invalid for time-series forecasting?
**Answer**: Time-series observations are non-independent and follow strict temporal autocorrelation ($y_t$ depends on $y_{t-1}$). Random k-fold cross-validation shuffles observations, using future data points to predict past dates, violating physical causality and producing artificially optimistic, non-generalizable accuracy metrics. A **strict chronological train/validation/test split** is mandatory.

#### Q11. What is the Naive Persistence Baseline model and why is it essential?
**Answer**: The Naive Persistence model predicts tomorrow's consumption as today's consumption ($\hat{y}_{t+1} = y_t$). It serves as the baseline ground truth: any complex machine learning algorithm (Linear Regression, Random Forest) is only considered practically valuable if it demonstrably beats the persistence baseline on out-of-sample RMSE and MAE.

#### Q12. Why did Random Forest Regression outperform Linear Regression in your experiments?
**Answer**: Household electrical consumption contains complex, non-linear interactions between seasonal calendar variables (summer vs. winter), day-of-week occupancy shifts (weekdays vs. weekends), and electrical baseload standard deviations. Linear regression assumes linear additivity, whereas Random Forest constructs an ensemble of de-correlated decision trees capable of partitioning non-linear feature sub-spaces.

#### Q13. Explain the difference between MAE, RMSE, and $R^2$.
**Answer**:
- **MAE (Mean Absolute Error)** measures the average magnitude of absolute errors in physical units (kWh) with linear weighting.
- **RMSE (Root Mean Squared Error)** squares individual errors before averaging, penalizing large outlier errors heavily.
- **$R^2$ (Coefficient of Determination)** indicates the proportion of variance in electricity consumption explained by model features relative to a simple horizontal mean line ($R^2 \in (-\infty, 1]$).

---

### 4. Dataset Characteristics & Physics

#### Q14. What are the physical units in the UCI Household Power Consumption dataset, and how were they converted?
**Answer**:
- `Global_active_power` is recorded in **kilowatts (kW)** (instantaneous power). Energy in kilowatt-hours (kWh) for a 1-minute interval is calculated as: $\text{Energy} = P \times (1/60 \text{ hr})$.
- `Sub_metering_1`, `Sub_metering_2`, and `Sub_metering_3` are recorded in **Watt-hours (Wh)**. They are converted to kWh via division by 1,000 ($\text{kWh} = \text{Wh} / 1000$).

#### Q15. What do the three electrical sub-meters represent?
**Answer**:
- **Sub-metering 1**: Kitchen appliances (dishwasher, microwave, electric oven).
- **Sub-metering 2**: Laundry room (washing machine, tumble dryer, refrigerator, light).
- **Sub-metering 3**: Climate control and hot water (electric water heater and air conditioner).

#### Q16. How did your pipeline handle missing values (`?`) in the dataset?
**Answer**: Missing values constitute 1.25% (25,979 minutes) of readings. Rather than fabricating or linearly interpolating extended sensor downtime (which distorts true variance and creates artificial consumption), invalid records were excluded from minute summations, and daily completeness ratios were calculated. Days with completeness $< 85\%$ were flagged as invalid for ML training.

---

### 5. Dashboard Data Model (Power BI design, Streamlit implementation)

> The dashboard we run is the Streamlit app. The star-schema tables below are exported as CSV and were designed for Power BI; no Power BI report was built.

#### Q17. What data modeling schema was adopted in Power BI, and why?
**Answer**: A **Star Schema** was implemented. A centralized date dimension (`dim_calendar`) with a 1-to-many relationship filters three transactional fact tables (`fact_daily_energy`, `fact_hourly_energy`, `fact_forecast_comparison`). Star schemas optimize VertiPaq engine compression, maximize DAX query performance, and eliminate ambiguous circular relationship paths.

#### Q18. What is the purpose of DAX Time Intelligence functions in the dashboard?
**Answer**: DAX Time Intelligence functions (such as `DATESINPERIOD` and `DATEADD`) allow dynamic calculation of rolling metrics across flexible user-selected date slicers—such as 7-day and 30-day moving averages—to smooth high-frequency daily noise and expose underlying macro energy trends.

---

### 6. Sustainability & UN SDG 7 Alignment

#### Q19. How does this project directly contribute to UN Sustainable Development Goal 7?
**Answer**: UN SDG 7 focuses on "Affordable and Clean Energy," specifically Target 7.3 (doubling global energy efficiency). By analyzing diurnal demand patterns and forecasting next-day load, the system empowers grid operators and consumers to perform **demand-side peak shaving** and shift high-energy discretionary activities away from peak stress periods.

#### Q20. What is Peak Shaving and Load Shifting, and what is its quantified impact?
**Answer**: Our analytical findings demonstrate that household electricity demand peaks between 18:00 and 21:00 (averaging 1.71 kW) and drops to a valley between 01:00 and 05:00 (averaging 0.47 kW). Shifting 15% of flexible appliance loads to off-peak nocturnal hours flattens the household's load curve. How much a household saves depends on its time-of-use tariff; this dataset has no tariff data, so no saving is quantified.

#### Q21. How were consumption anomalies detected, and why are they relevant to energy waste?
**Answer**: Anomalies were identified using a statistical threshold: days where consumption exceeded $\mu + 2\sigma$ ($46.2 \text{ kWh}$). Detecting these 49 historical anomaly days alerts consumers to malfunctioning appliances, equipment left on continuously, or insulation degradation.

---

### 7. Software Engineering & Verification

#### Q22. How did you verify the mathematical correctness of your MapReduce implementation?
**Answer**: Two ways. `hadoop/run_mapreduce.py` runs the mapper and reducer on the 5,000-row sample and compares the result with an independent pandas calculation. On the cluster, `run_on_mac.sh` compares the daily totals produced by the YARN job over all 2,075,259 rows with the daily table produced by the cleaning step: all 1,433 days match, with a largest difference of 0.0001 kWh (rounding in the reducer's four-decimal output). `tests/test_cluster_outputs.py` repeats that check automatically.

#### Q23. What automated tests were implemented, and how does the CI pipeline work?
**Answer**: A 35-test suite was implemented using `pytest` spanning preprocessing unit conversions, MapReduce streaming boundary conditions, data leakage prevention, chronological splitting, model metric correctness, and Power BI export schema validity. A GitHub Actions workflow (`.github/workflows/ci.yml`) executes these tests automatically on push.

---

### 8. Our Cluster Setup (Batch 30 additions)

#### Q24. How is the Hadoop cluster set up, and what exactly runs on it?
**Answer**: It is a single-node (pseudo-distributed) Hadoop 3.3.6 cluster on a MacBook: one NameNode and one DataNode for HDFS, and one ResourceManager and one NodeManager for YARN, with replication factor 1. Two Hadoop Streaming MapReduce jobs run on YARN over the full 2,075,259-row file: daily energy totals, and the hour-of-day load profile. The 12 HiveQL queries also run as MapReduce jobs on YARN through HiveServer2.

#### Q25. What is your second MapReduce job, and what did it find?
**Answer**: `mapper_hourly.py` keys every valid one-minute reading by its hour of day and emits the interval energy and the power; `reducer_hourly.py` returns total energy, reading count, average power and peak power for each of the 24 hours. It shows demand lowest around 03:00 to 04:00 (about 0.44 kW) and highest around 20:00 to 21:00 (about 1.9 kW).

#### Q26. Is Hive really installed, or is it Spark SQL?
**Answer**: Both exist. Apache Hive 4.0.1 is installed with HiveServer2 and an embedded Derby metastore. `hive/schema.hql` creates an external table over the raw file in HDFS, a daily table stored as ORC and partitioned by year, and an hourly table stored as Parquet. `hive/load_cleaned_tables.hql` loads them with dynamic partitioning, and `hive/run_hive_on_cluster.py` runs the 12 queries through beeline and saves the results in `hive/cluster_results/`. Separately, `hive/run_hive_analytics.py` runs the same analysis in Spark SQL; the two engines give the same numbers.

#### Q27. Why does a Hive query on a small table take 20 to 90 seconds?
**Answer**: Hive uses the MapReduce execution engine here. Every aggregation is compiled into one or more MapReduce jobs, and each job has to start an ApplicationMaster and task containers on YARN. That fixed start-up cost dominates on small tables. A query with a join and an ORDER BY (Query 9) needs several jobs in sequence. Tez or Spark as the engine would cut this sharply.

#### Q28. Why did the Hive header row appear as NULL, and how did you fix it?
**Answer**: The cleaned CSV files have a header line. The table property `skip.header.line.count` was not applied when Hive's MapReduce engine read the files, so the header was parsed as a row of NULLs. The load script now filters it out (`WHERE date_iso <> 'Date_ISO'`), and the raw-table query filters `record_date <> 'Date'`.

#### Q29. What problem did you hit running Hive on Hadoop 3.3.6, and how was it solved?
**Answer**: The first INSERT into the ORC table failed with `NoSuchMethodError: com.google.protobuf.Internal.checkNotNull`. Hadoop ships protobuf 2.5 while Hive's ORC writer needs protobuf 3, and the Hadoop jar came first on the task classpath. Setting `mapreduce.job.user.classpath.first=true` in `hive-site.xml` puts the job's own jars first and fixes it.

#### Q30. Is 2 million rows really big data?
**Answer**: No. At 126.8 MB the file fits in one HDFS block. The project demonstrates the full workflow (distributed storage, batch jobs on YARN, a Hive warehouse, Spark features and MLlib models) on a real public dataset, and the same code would run unchanged on a multi-node cluster with a larger file.

