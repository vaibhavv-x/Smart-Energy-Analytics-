# Experimental Results & Performance Analysis

## Smart Energy Consumption Analytics & Forecasting
**Batch**: 30  
**Team**: Vaibhav (AP23110010425) & Saubhagya Kashyap (AP23110010439)

---

## 1. Dataset Processing & Validation Summary

| Metric | Measured Value | Unit / Note |
|---|---|---|
| Total Raw Minute Readings | **2,075,259** | 100.0% |
| Valid Power Readings | **2,049,280** | 98.7482% |
| Missing Power Readings (`?`) | **25,979** | 1.2518% |
| Duplicate Timestamps Detected | **0** | Perfect sequential sampling |
| Monitored Calendar Period | **Dec 16, 2006 – Nov 26, 2010** | 47 continuous months (1,433 days) |
| Valid Calendar Days ($\ge 85\%$ complete) | **1,420** | 99.09% of days |
| Total Recorded Energy | **37,283.75** | kWh |
| Mean Daily Consumption | **26.18** | kWh/day |
| Maximum Daily Consumption | **69.83** | kWh/day (Recorded 2007-06-04) |
| Minimum Valid Daily Consumption | **3.85** | kWh/day |

---

## 2. Hadoop MapReduce Execution Evidence

**Local check (sample).** `hadoop/run_mapreduce.py` pipes the 5,000-row sample through the mapper, a sort and the reducer, and compares the five daily totals with an independent pandas calculation. They agree to within rounding.

**Cluster run (full dataset).** The same mapper and reducer run as a Hadoop Streaming job on YARN over all 2,075,259 rows:

| Parameter | Value |
|---|---|
| Map input records | 2,075,260 (including the header line) |
| Valid readings aggregated | 2,049,280 |
| Daily totals produced | 1,433 |
| Days matching the pipeline's daily table | 1,433 |
| Largest difference | 0.0001 kWh |

---

## 3. HiveQL Analytical Findings

All figures are from our run on Apache Hive and agree with the Spark SQL cross-check.

### A. Sub-Metering Disaggregation (Query 8)
- **Total energy**: 37,172.66 kWh (across 1,420 valid days)
- **Sub-metering 3 (water heater and air conditioner)**: 13,203.45 kWh (**35.52%**), the largest metered load.
- **Sub-metering 2 (laundry)**: 2,649.12 kWh (**7.13%**)
- **Sub-metering 1 (kitchen)**: 2,290.73 kWh (**6.16%**)
- **Unmetered remainder**: 19,029.66 kWh (**51.19%**): lighting, electronics, small appliances, refrigeration.

### B. Weekday versus Weekend Patterns (Query 6)
- **Weekdays (Mon–Fri)**: mean **24.84 kWh/day** (1,019 days)
- **Weekends (Sat–Sun)**: mean **29.59 kWh/day** (401 days)
- Weekend consumption is **19.1% higher** than weekday consumption.

### C. Peak Demand Hours (Queries 3 and 4)
The five hours with the highest average consumption:

| Rank | Hour | Average energy (kWh per hour) |
|---|---|---|
| 1 | 20:00 – 21:00 | 1.90 |
| 2 | 21:00 – 22:00 | 1.87 |
| 3 | 19:00 – 20:00 | 1.73 |
| 4 | 07:00 – 08:00 | 1.50 |
| 5 | 08:00 – 09:00 | 1.46 |

The quietest hour is 04:00 – 05:00 at 0.44 kWh, so the busiest hour uses 4.3 times as much as the quietest. The evening peak (18:00 – 21:59) averages 1.71 kW and the night valley (01:00 – 05:59) averages 0.47 kW.

### D. Seasonal Pattern (Query 7)
Average daily consumption is highest in December (35.6 kWh) and January (35.1 kWh) and lowest in August (13.7 kWh) and July (16.8 kWh).

### E. Anomaly Days
Days above the mean plus two standard deviations (46.2 kWh) are flagged: 49 of the 1,420 valid days.

---

## 4. Machine Learning Forecasting Model Comparison

Forecasting Next-Day Household Electricity Consumption ($E_t$) on the strict chronological test period ($N = 213$ days, April 2010 – November 2010):

| Model | Algorithm / Type | Validation RMSE | Test MAE (kWh) | Test RMSE (kWh) | Test $R^2$ | Test MAPE (%) |
|---|---|---|---|---|---|---|
| **Naive Baseline** | Persistence ($y_{t-1}$) | 8.4182 | 4.4998 | 6.4155 | 0.2024 | 19.20% |
| **Linear Regression** | Spark MLlib ElasticNet | 6.2883 | 3.9607 | 5.3711 | 0.4409 | 18.21% |
| **Random Forest** | Spark MLlib (40 trees, depth 5) | **6.1262** | **3.8203** | **5.1588** | **0.4843** | **18.19%** |

### Performance Discussion & Key Takeaways:
1. **Baseline Outperformance**: Both MLlib models substantially outperformed the Naive Persistence baseline. The Random Forest model achieved an RMSE reduction of **19.59%** (5.16 kWh vs. 6.42 kWh) and more than doubled the explained variance ($R^2 = 0.4843$ vs. $0.2024$).
2. **Non-Linear Dynamics**: Random Forest surpassed Linear Regression across all metrics (Test RMSE 5.16 vs 5.37 kWh), demonstrating that non-linear interaction terms between seasonal month, day of week, and multi-day rolling standard deviations are essential for modeling stochastic household electricity behavior.
3. **Model Selection**: Random Forest Regressor was objectively selected as the best model based on having the lowest Validation RMSE (6.1262).

---

## 5. Cluster Run Results (Batch 30, 15 Nov 2026)

All numbers below come from our own run of `bash run_on_mac.sh` on a single-node cluster (Apple M1, 8 GB RAM; Hadoop 3.3.6, Hive 4.0.1, PySpark 3.5.3, Java 11).

### 5.1 MapReduce on YARN

| Job | Input | Map tasks | Reduce tasks | Output |
|---|---|---|---|---|
| Daily energy totals | 2,075,259 rows from HDFS | 2 | 1 | 1,433 daily totals |
| Hour-of-day load profile | 2,075,259 rows from HDFS | 2 | 1 | 24 hourly rows |

- The daily totals match the pipeline's daily table on all 1,433 days; the largest difference is 0.0001 kWh.
- Hour-of-day profile: average demand is lowest at 04:00 (0.44 kW) and highest at 20:00 (1.90 kW). The highest single reading is 11.12 kW.

### 5.2 Apache Hive (HiveServer2, MapReduce engine on YARN)

| Query | Rows | Seconds |
|---|---|---|
| Q1: Daily Electricity Consumption Time-Series | 1420 | 20.6 |
| Q2: Monthly Electricity Consumption Aggregations | 48 | 41.8 |
| Q3: Average Hourly Consumption Profile (24-Hour Diurnal Cycle) | 24 | 43.4 |
| Q4: Peak Consumption Hours Identification | 5 | 42.3 |
| Q5: Top 10 Highest Consumption Dates (Historical Peaks) | 10 | 21.3 |
| Q6: Weekday versus Weekend Energy Usage Patterns | 2 | 20.3 |
| Q7: Seasonal Monthly Energy Trends | 12 | 40.9 |
| Q8: Sub-Metering End-Use Distribution & Breakdown | 1 | 21.5 |
| Q9: Year-on-Year Change in Monthly Consumption | 36 | 82.0 |
| Q10: Share of High-Consumption Days (above 40 kWh) per Year | 5 | 39.9 |
| Q11: Consumption by Time-of-Day Band | 4 | 60.2 |
| Q12: Data Quality per Year on the Raw Table (2,075,259 rows in HDFS) | 5 | 45.1 |

Results agree with the Spark SQL cross-check (for example, total valid-day energy 37,172.66 kWh in both).

**Query 10: share of high-consumption days (above 40 kWh) per year**

| year_num | valid_days | high_days | high_days_pct |
|---|---|---|---|
| 2006 | 15 | 8 | 53.33 |
| 2007 | 362 | 44 | 12.15 |
| 2008 | 366 | 25 | 6.83 |
| 2009 | 361 | 23 | 6.37 |
| 2010 | 316 | 13 | 4.11 |

**Query 11: consumption by time-of-day band**

| band | total_kwh | avg_power_kw | share_pct |
|---|---|---|---|
| 1 Night (00-05) | 4301.19 | 0.5037 | 11.54 |
| 2 Morning (06-11) | 10791.77 | 1.2657 | 28.94 |
| 3 Afternoon (12-17) | 9145.65 | 1.0716 | 24.53 |
| 4 Evening (18-23) | 13045.14 | 1.5251 | 34.99 |

**Query 12: data quality per year, computed on the raw table**

| year_num | total_readings | valid_readings | missing_readings | missing_pct | avg_voltage_v | peak_power_kw |
|---|---|---|---|---|---|---|
| 2006 | 21996 | 21992 | 4 | 0.018 | 241.44 | 9.132 |
| 2007 | 525600 | 521669 | 3931 | 0.748 | 239.38 | 10.67 |
| 2008 | 527040 | 526905 | 135 | 0.026 | 240.63 | 10.348 |
| 2009 | 525600 | 521320 | 4280 | 0.814 | 241.89 | 11.122 |
| 2010 | 475023 | 457394 | 17629 | 3.711 | 241.52 | 9.724 |

2006 has only 15 valid days (the data starts on 16 December), so its figures are not comparable with full years. 2010 has the most missing readings (3.7%).

### 5.3 Forecasting (features and training data read from HDFS)

| Model | MAE (kWh) | RMSE (kWh) | R² | MAPE |
|---|---|---|---|---|
| Naive baseline | 4.4998 | 6.4155 | 0.2024 | 19.20% |
| Linear Regression | 3.9607 | 5.3711 | 0.4409 | 18.21% |
| Random Forest (selected) | 3.8203 | 5.1588 | 0.4843 | 18.19% |

### 5.4 Tests

35 automated tests pass, including five that check the cluster outputs (`tests/test_cluster_outputs.py`).
