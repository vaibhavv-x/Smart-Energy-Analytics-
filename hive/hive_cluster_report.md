# Apache Hive Execution Report (real cluster)

Executed through HiveServer2 (`jdbc:hive2://localhost:10000`) with the MapReduce engine on YARN. Tables live in the Hive warehouse in HDFS (`/smart-energy/hive/warehouse`).

| Query | Rows | Seconds |
|---|---|---|
| Q1: Daily Electricity Consumption Time-Series | 1420 | 20.1 |
| Q2: Monthly Electricity Consumption Aggregations | 48 | 40.7 |
| Q3: Average Hourly Consumption Profile (24-Hour Diurnal Cycle) | 24 | 41.2 |
| Q4: Peak Consumption Hours Identification | 5 | 40.3 |
| Q5: Top 10 Highest Consumption Dates (Historical Peaks) | 10 | 21.0 |
| Q6: Weekday versus Weekend Energy Usage Patterns | 2 | 22.0 |
| Q7: Seasonal Monthly Energy Trends | 12 | 42.3 |
| Q8: Sub-Metering End-Use Distribution & Breakdown | 1 | 22.1 |
| Q9: Year-on-Year Change in Monthly Consumption | 36 | 83.7 |
| Q10: Share of High-Consumption Days (above 40 kWh) per Year | 5 | 41.3 |
| Q11: Consumption by Time-of-Day Band | 4 | 61.5 |
| Q12: Data Quality per Year on the Raw Table (2,075,259 rows in HDFS) | 5 | 43.8 |

The forecasting feature table (`daily_features`, 1413 rows) is exported to `hive/cluster_results/daily_features.csv` for the R scripts.

## Query 1: Daily Electricity Consumption Time-Series

```sql
SELECT 
    consumption_date,
    ROUND(total_energy_kwh, 4) AS daily_energy_kwh,
    reading_count,
    ROUND(completeness_ratio * 100, 2) AS completeness_pct
FROM daily_energy_consumption
WHERE is_valid_day = 1
ORDER BY consumption_date
```

Result file: `hive/cluster_results/q01.csv` (1420 rows). First rows:

```
consumption_date,daily_energy_kwh,reading_count,completeness_pct
2006-12-17,56.5077,1440,100.0
2006-12-18,36.7304,1440,100.0
2006-12-19,27.7699,1440,100.0
2006-12-20,37.0958,1440,100.0
2006-12-21,28.6104,1438,99.86
2006-12-22,39.0223,1440,100.0
2006-12-23,79.5564,1440,100.0
2006-12-24,42.5002,1440,100.0
2006-12-25,45.7187,1440,100.0
2006-12-26,65.5685,1440,100.0
```

## Query 2: Monthly Electricity Consumption Aggregations

```sql
SELECT 
    year_num,
    month_num,
    month_name,
    COUNT(*) AS valid_days_in_month,
    ROUND(SUM(total_energy_kwh), 2) AS total_monthly_kwh,
    ROUND(AVG(total_energy_kwh), 2) AS avg_daily_kwh,
    ROUND(MAX(total_energy_kwh), 2) AS max_daily_kwh
FROM daily_energy_consumption
WHERE is_valid_day = 1
GROUP BY year_num, month_num, month_name
ORDER BY year_num, month_num
```

Result file: `hive/cluster_results/q02.csv` (48 rows). First rows:

```
year_num,month_num,month_name,valid_days_in_month,total_monthly_kwh,avg_daily_kwh,max_daily_kwh
2006,12,December,15,676.74,45.12,79.56
2007,1,January,31,1150.2,37.1,56.79
2007,2,February,28,941.48,33.62,67.16
2007,3,March,31,981.04,31.65,58.49
2007,4,April,27,578.97,21.44,46.43
2007,5,May,31,733.48,23.66,35.9
2007,6,June,30,594.71,19.82,35.8
2007,7,July,31,495.06,15.97,27.03
2007,8,August,31,568.27,18.33,27.6
2007,9,September,30,697.88,23.26,38.28
```

## Query 3: Average Hourly Consumption Profile (24-Hour Diurnal Cycle)

```sql
SELECT 
    hour_of_day,
    ROUND(AVG(total_energy_kwh), 4) AS avg_hourly_energy_kwh,
    ROUND(AVG(avg_power_kw), 4) AS avg_power_kw,
    ROUND(AVG(avg_voltage_v), 2) AS avg_voltage_v
FROM hourly_energy_consumption
GROUP BY hour_of_day
ORDER BY hour_of_day
```

Result file: `hive/cluster_results/q03.csv` (24 rows). First rows:

```
hour_of_day,avg_hourly_energy_kwh,avg_power_kw,avg_voltage_v
0,0.6589,0.6596,242.4
1,0.5393,0.5393,241.72
2,0.4806,0.4806,242.59
3,0.4448,0.4448,242.68
4,0.4438,0.4438,242.43
5,0.4537,0.4537,242.09
6,0.7916,0.7916,241.94
7,1.5016,1.5024,239.92
8,1.4606,1.4609,239.5
9,1.3316,1.3316,239.42
```

## Query 4: Peak Consumption Hours Identification

```sql
SELECT 
    hour_of_day,
    ROUND(AVG(total_energy_kwh), 4) AS avg_hourly_energy_kwh,
    ROUND(MAX(total_energy_kwh), 4) AS peak_recorded_hourly_kwh,
    ROUND(AVG(avg_power_kw), 4) AS avg_power_demand_kw
FROM hourly_energy_consumption
GROUP BY hour_of_day
ORDER BY avg_hourly_energy_kwh DESC
LIMIT 5
```

Result file: `hive/cluster_results/q04.csv` (5 rows). First rows:

```
hour_of_day,avg_hourly_energy_kwh,peak_recorded_hourly_kwh,avg_power_demand_kw
20,1.899,6.5196,1.8991
21,1.8744,6.3639,1.8761
19,1.7318,6.496,1.7334
7,1.5016,4.4166,1.5024
8,1.4606,4.4189,1.4609
```

## Query 5: Top 10 Highest Consumption Dates (Historical Peaks)

```sql
SELECT 
    consumption_date,
    day_of_week,
    month_name,
    year_num,
    ROUND(total_energy_kwh, 2) AS total_energy_kwh,
    ROUND(max_power_kw, 2) AS peak_power_kw
FROM daily_energy_consumption
WHERE is_valid_day = 1
ORDER BY total_energy_kwh DESC
LIMIT 10
```

Result file: `hive/cluster_results/q05.csv` (10 rows). First rows:

```
consumption_date,day_of_week,month_name,year_num,total_energy_kwh,peak_power_kw
2006-12-23,Saturday,December,2006,79.56,8.7
2007-02-03,Saturday,February,2007,67.16,7.9
2006-12-26,Tuesday,December,2006,65.57,6.5
2007-02-18,Sunday,February,2007,63.83,7.16
2007-02-04,Sunday,February,2007,59.93,7.7
2007-02-11,Sunday,February,2007,59.52,7.43
2007-03-31,Saturday,March,2007,58.49,7.1
2006-12-31,Sunday,December,2006,58.24,6.72
2007-03-11,Sunday,March,2007,58.01,7.14
2007-01-21,Sunday,January,2007,56.79,8.02
```

## Query 6: Weekday versus Weekend Energy Usage Patterns

```sql
SELECT 
    CASE WHEN is_weekend = 1 THEN 'Weekend' ELSE 'Weekday' END AS day_category,
    COUNT(*) AS total_days,
    ROUND(AVG(total_energy_kwh), 2) AS avg_daily_energy_kwh,
    ROUND(MIN(total_energy_kwh), 2) AS min_daily_energy_kwh,
    ROUND(MAX(total_energy_kwh), 2) AS max_daily_energy_kwh,
    ROUND(STDDEV(total_energy_kwh), 2) AS std_dev_energy_kwh
FROM daily_energy_consumption
WHERE is_valid_day = 1
GROUP BY is_weekend
```

Result file: `hive/cluster_results/q06.csv` (2 rows). First rows:

```
day_category,total_days,avg_daily_energy_kwh,min_daily_energy_kwh,max_daily_energy_kwh,std_dev_energy_kwh
Weekday,1019,24.84,4.17,65.57,8.73
Weekend,401,29.59,4.24,79.56,11.99
```

## Query 7: Seasonal Monthly Energy Trends

```sql
SELECT 
    month_num,
    month_name,
    ROUND(AVG(total_energy_kwh), 2) AS seasonal_avg_daily_kwh,
    ROUND(SUM(total_energy_kwh), 2) AS cumulative_energy_kwh,
    ROUND(AVG(avg_voltage_v), 2) AS seasonal_avg_voltage
FROM daily_energy_consumption
WHERE is_valid_day = 1
GROUP BY month_num, month_name
ORDER BY month_num
```

Result file: `hive/cluster_results/q07.csv` (12 rows). First rows:

```
month_num,month_name,seasonal_avg_daily_kwh,cumulative_energy_kwh,seasonal_avg_voltage
1,January,35.07,4243.5,242.16
2,February,31.2,3525.23,241.46
3,March,29.55,3605.31,241.53
4,April,25.16,2943.36,241.07
5,May,24.71,3063.88,239.01
6,June,21.83,2554.47,239.91
7,July,16.8,2082.66,240.0
8,August,13.69,1615.3,240.17
9,September,23.41,2715.03,240.45
10,October,27.28,3383.24,240.78
```

## Query 8: Sub-Metering End-Use Distribution & Breakdown

```sql
SELECT 
    ROUND(SUM(total_energy_kwh), 2) AS total_household_kwh,
    ROUND(SUM(sub_metering_1_kwh), 2) AS sub1_kitchen_kwh,
    ROUND(SUM(sub_metering_2_kwh), 2) AS sub2_laundry_kwh,
    ROUND(SUM(sub_metering_3_kwh), 2) AS sub3_climate_water_kwh,
    ROUND(SUM(sub_remainder_kwh), 2) AS unmetered_remainder_kwh,
    ROUND(SUM(sub_metering_1_kwh) / SUM(total_energy_kwh) * 100, 2) AS kitchen_percentage,
    ROUND(SUM(sub_metering_2_kwh) / SUM(total_energy_kwh) * 100, 2) AS laundry_percentage,
    ROUND(SUM(sub_metering_3_kwh) / SUM(total_energy_kwh) * 100, 2) AS climate_water_percentage,
    ROUND(SUM(sub_remainder_kwh) / SUM(total_energy_kwh) * 100, 2) AS remainder_percentage
FROM daily_energy_consumption
WHERE is_valid_day = 1
```

Result file: `hive/cluster_results/q08.csv` (1 rows). First rows:

```
total_household_kwh,sub1_kitchen_kwh,sub2_laundry_kwh,sub3_climate_water_kwh,unmetered_remainder_kwh,kitchen_percentage,laundry_percentage,climate_water_percentage,remainder_percentage
37172.66,2290.73,2649.12,13203.45,19029.66,6.16,7.13,35.52,51.19
```

## Query 9: Year-on-Year Change in Monthly Consumption

```sql
SELECT
    cur.year_num,
    cur.month_num,
    ROUND(cur.avg_daily_kwh, 2) AS avg_daily_kwh,
    ROUND(prev.avg_daily_kwh, 2) AS prev_year_avg_daily_kwh,
    ROUND((cur.avg_daily_kwh - prev.avg_daily_kwh) / prev.avg_daily_kwh * 100, 2) AS change_pct
FROM (
    SELECT year_num, month_num, AVG(total_energy_kwh) AS avg_daily_kwh
    FROM daily_energy_consumption WHERE is_valid_day = 1
    GROUP BY year_num, month_num
) cur
JOIN (
    SELECT year_num + 1 AS next_year, month_num, AVG(total_energy_kwh) AS avg_daily_kwh
    FROM daily_energy_consumption WHERE is_valid_day = 1
    GROUP BY year_num, month_num
) prev
  ON cur.year_num = prev.next_year AND cur.month_num = prev.month_num
ORDER BY cur.year_num, cur.month_num
```

Result file: `hive/cluster_results/q09.csv` (36 rows). First rows:

```
cur.year_num,cur.month_num,avg_daily_kwh,prev_year_avg_daily_kwh,change_pct
2007,12,39.03,45.12,-13.48
2008,1,35.04,37.1,-5.57
2008,2,28.35,33.62,-15.68
2008,3,29.89,31.65,-5.56
2008,4,26.78,21.44,24.9
2008,5,24.58,23.66,3.89
2008,6,23.86,19.82,20.35
2008,7,19.07,15.97,19.44
2008,8,6.64,18.33,-63.8
2008,9,23.7,23.26,1.9
```

## Query 10: Share of High-Consumption Days (above 40 kWh) per Year

```sql
SELECT
    year_num,
    COUNT(*) AS valid_days,
    SUM(CASE WHEN total_energy_kwh > 40 THEN 1 ELSE 0 END) AS high_days,
    ROUND(SUM(CASE WHEN total_energy_kwh > 40 THEN 1 ELSE 0 END) / COUNT(*) * 100, 2) AS high_days_pct
FROM daily_energy_consumption
WHERE is_valid_day = 1
GROUP BY year_num
ORDER BY year_num
```

Result file: `hive/cluster_results/q10.csv` (5 rows). First rows:

```
year_num,valid_days,high_days,high_days_pct
2006,15,8,53.33
2007,362,44,12.15
2008,366,25,6.83
2009,361,23,6.37
2010,316,13,4.11
```

## Query 11: Consumption by Time-of-Day Band

```sql
SELECT
    band,
    ROUND(total_kwh, 2) AS total_kwh,
    ROUND(avg_power_kw, 4) AS avg_power_kw,
    ROUND(total_kwh / SUM(total_kwh) OVER () * 100, 2) AS share_pct
FROM (
    SELECT band, SUM(total_energy_kwh) AS total_kwh, AVG(avg_power_kw) AS avg_power_kw
    FROM (
        SELECT
            CASE
                WHEN hour_of_day < 6 THEN '1 Night (00-05)'
                WHEN hour_of_day < 12 THEN '2 Morning (06-11)'
                WHEN hour_of_day < 18 THEN '3 Afternoon (12-17)'
                ELSE '4 Evening (18-23)'
            END AS band,
            total_energy_kwh,
            avg_power_kw
        FROM hourly_energy_consumption
    ) h
    GROUP BY band
) b
ORDER BY band
```

Result file: `hive/cluster_results/q11.csv` (4 rows). First rows:

```
band,total_kwh,avg_power_kw,share_pct
1 Night (00-05),4301.19,0.5037,11.54
2 Morning (06-11),10791.77,1.2657,28.94
3 Afternoon (12-17),9145.65,1.0717,24.53
4 Evening (18-23),13045.14,1.5252,34.99
```

## Query 12: Data Quality per Year on the Raw Table (2,075,259 rows in HDFS)

```sql
SELECT
    split(record_date, '/')[2] AS year_num,
    COUNT(*) AS total_readings,
    COUNT(global_active_power) AS valid_readings,
    COUNT(*) - COUNT(global_active_power) AS missing_readings,
    ROUND((COUNT(*) - COUNT(global_active_power)) / COUNT(*) * 100, 3) AS missing_pct,
    ROUND(AVG(voltage), 2) AS avg_voltage_v,
    ROUND(MAX(global_active_power), 3) AS peak_power_kw
FROM raw_household_power
WHERE record_date <> 'Date'
GROUP BY split(record_date, '/')[2]
ORDER BY year_num
```

Result file: `hive/cluster_results/q12.csv` (5 rows). First rows:

```
year_num,total_readings,valid_readings,missing_readings,missing_pct,avg_voltage_v,peak_power_kw
2006,21996,21992,4,0.018,241.44,9.132
2007,525600,521669,3931,0.748,239.38,10.67
2008,527040,526905,135,0.026,240.63,10.348
2009,525600,521320,4280,0.814,241.89,11.122
2010,475023,457394,17629,3.711,241.52,9.724
```
