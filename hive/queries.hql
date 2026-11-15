-- =============================================================================
-- HiveQL Analytical Queries
-- Project: Smart Energy Consumption Analytics & Forecasting
-- Subject: Big Data Analytics (BDA)
-- =============================================================================

USE smart_energy_db;

-- -----------------------------------------------------------------------------
-- Query 1: Daily Electricity Consumption Time-Series
-- Objective: Track day-by-day aggregate electricity usage across valid days
-- -----------------------------------------------------------------------------
SELECT 
    consumption_date,
    ROUND(total_energy_kwh, 4) AS daily_energy_kwh,
    reading_count,
    ROUND(completeness_ratio * 100, 2) AS completeness_pct
FROM daily_energy_consumption
WHERE is_valid_day = 1
ORDER BY consumption_date;

-- -----------------------------------------------------------------------------
-- Query 2: Monthly Electricity Consumption Aggregations
-- Objective: Assess calendar month totals, average daily demand, and active days
-- -----------------------------------------------------------------------------
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
ORDER BY year_num, month_num;

-- -----------------------------------------------------------------------------
-- Query 3: Average Hourly Consumption Profile (24-Hour Diurnal Cycle)
-- Objective: Understand intra-day demand curve for load-shifting and peak shaving
-- -----------------------------------------------------------------------------
SELECT 
    hour_of_day,
    ROUND(AVG(total_energy_kwh), 4) AS avg_hourly_energy_kwh,
    ROUND(AVG(avg_power_kw), 4) AS avg_power_kw,
    ROUND(AVG(avg_voltage_v), 2) AS avg_voltage_v
FROM hourly_energy_consumption
GROUP BY hour_of_day
ORDER BY hour_of_day;

-- -----------------------------------------------------------------------------
-- Query 4: Peak Consumption Hours Identification
-- Objective: Pinpoint top 5 highest electricity demand hours in the day
-- -----------------------------------------------------------------------------
SELECT 
    hour_of_day,
    ROUND(AVG(total_energy_kwh), 4) AS avg_hourly_energy_kwh,
    ROUND(MAX(total_energy_kwh), 4) AS peak_recorded_hourly_kwh,
    ROUND(AVG(avg_power_kw), 4) AS avg_power_demand_kw
FROM hourly_energy_consumption
GROUP BY hour_of_day
ORDER BY avg_hourly_energy_kwh DESC
LIMIT 5;

-- -----------------------------------------------------------------------------
-- Query 5: Top 10 Highest Consumption Dates (Historical Peaks)
-- Objective: Identify extreme consumption events for grid stress analysis
-- -----------------------------------------------------------------------------
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
LIMIT 10;

-- -----------------------------------------------------------------------------
-- Query 6: Weekday versus Weekend Energy Usage Patterns
-- Objective: Contrast behavioral patterns between working days and weekends
-- -----------------------------------------------------------------------------
SELECT 
    CASE WHEN is_weekend = 1 THEN 'Weekend' ELSE 'Weekday' END AS day_category,
    COUNT(*) AS total_days,
    ROUND(AVG(total_energy_kwh), 2) AS avg_daily_energy_kwh,
    ROUND(MIN(total_energy_kwh), 2) AS min_daily_energy_kwh,
    ROUND(MAX(total_energy_kwh), 2) AS max_daily_energy_kwh,
    ROUND(STDDEV(total_energy_kwh), 2) AS std_dev_energy_kwh
FROM daily_energy_consumption
WHERE is_valid_day = 1
GROUP BY is_weekend;

-- -----------------------------------------------------------------------------
-- Query 7: Seasonal Monthly Energy Trends
-- Objective: Measure seasonal variations across the 12 calendar months
-- -----------------------------------------------------------------------------
SELECT 
    month_num,
    month_name,
    ROUND(AVG(total_energy_kwh), 2) AS seasonal_avg_daily_kwh,
    ROUND(SUM(total_energy_kwh), 2) AS cumulative_energy_kwh,
    ROUND(AVG(avg_voltage_v), 2) AS seasonal_avg_voltage
FROM daily_energy_consumption
WHERE is_valid_day = 1
GROUP BY month_num, month_name
ORDER BY month_num;

-- -----------------------------------------------------------------------------
-- Query 8: Sub-Metering End-Use Distribution & Breakdown
-- Objective: Disaggregate household energy into Kitchen, Laundry, Climate, Remainder
-- -----------------------------------------------------------------------------
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
WHERE is_valid_day = 1;

-- =============================================================================
-- Additional queries (Batch 30)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Query 9: Year-on-Year Change in Monthly Consumption
-- Objective: Compare each month's average daily demand with the same month a year earlier
-- -----------------------------------------------------------------------------
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
ORDER BY cur.year_num, cur.month_num;

-- -----------------------------------------------------------------------------
-- Query 10: Share of High-Consumption Days (above 40 kWh) per Year
-- Objective: Track how often the household has a heavy-demand day
-- -----------------------------------------------------------------------------
SELECT
    year_num,
    COUNT(*) AS valid_days,
    SUM(CASE WHEN total_energy_kwh > 40 THEN 1 ELSE 0 END) AS high_days,
    ROUND(SUM(CASE WHEN total_energy_kwh > 40 THEN 1 ELSE 0 END) / COUNT(*) * 100, 2) AS high_days_pct
FROM daily_energy_consumption
WHERE is_valid_day = 1
GROUP BY year_num
ORDER BY year_num;

-- -----------------------------------------------------------------------------
-- Query 11: Consumption by Time-of-Day Band
-- Objective: Split energy use into night, morning, afternoon and evening for load shifting
-- -----------------------------------------------------------------------------
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
ORDER BY band;

-- -----------------------------------------------------------------------------
-- Query 12: Data Quality per Year on the Raw Table (2,075,259 rows in HDFS)
-- Objective: Count valid and missing one-minute readings straight from the raw file
-- -----------------------------------------------------------------------------
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
ORDER BY year_num;
