-- =============================================================================
-- Load the cleaned daily and hourly tables from HDFS into the Hive warehouse
-- Run after hive/schema.hql. The CSV files are put in HDFS by scripts/run_pipeline.py
-- (/smart-energy/cleaned/daily and /smart-energy/cleaned/hourly).
-- Each INSERT below runs as a MapReduce job on YARN.
-- =============================================================================

USE smart_energy_db;

SET hive.exec.dynamic.partition=true;
SET hive.exec.dynamic.partition.mode=nonstrict;

-- Staging table over the cleaned daily CSV (columns in file order)
DROP TABLE IF EXISTS stg_daily_csv;
CREATE EXTERNAL TABLE stg_daily_csv (
    date_iso STRING,
    energy_kwh DOUBLE,
    sub_metering_1_kwh DOUBLE,
    sub_metering_2_kwh DOUBLE,
    sub_metering_3_kwh DOUBLE,
    sub_remainder_kwh DOUBLE,
    avg_power_kw DOUBLE,
    max_power_kw DOUBLE,
    min_power_kw DOUBLE,
    avg_voltage_v DOUBLE,
    reading_count INT,
    date_copy STRING,
    completeness_ratio DOUBLE,
    is_valid_day INT,
    day_of_week STRING,
    day_of_week_num INT,
    is_weekend INT,
    month_num INT,
    month_name STRING,
    year_num INT
)
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
STORED AS TEXTFILE
LOCATION '/smart-energy/cleaned/daily'
TBLPROPERTIES ("skip.header.line.count"="1");

-- Staging table over the cleaned hourly CSV (columns in file order)
DROP TABLE IF EXISTS stg_hourly_csv;
CREATE EXTERNAL TABLE stg_hourly_csv (
    date_iso STRING,
    hour_of_day INT,
    energy_kwh DOUBLE,
    sub_metering_1_kwh DOUBLE,
    sub_metering_2_kwh DOUBLE,
    sub_metering_3_kwh DOUBLE,
    sub_remainder_kwh DOUBLE,
    avg_power_kw DOUBLE,
    avg_voltage_v DOUBLE,
    reading_count INT,
    datetime_hour STRING
)
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
STORED AS TEXTFILE
LOCATION '/smart-energy/cleaned/hourly'
TBLPROPERTIES ("skip.header.line.count"="1");

-- Daily table: ORC, partitioned by year (dynamic partitioning)
INSERT OVERWRITE TABLE daily_energy_consumption PARTITION (year_num)
SELECT
    date_iso,
    energy_kwh,
    avg_power_kw,
    max_power_kw,
    min_power_kw,
    avg_voltage_v,
    sub_metering_1_kwh,
    sub_metering_2_kwh,
    sub_metering_3_kwh,
    sub_remainder_kwh,
    reading_count,
    completeness_ratio,
    is_valid_day,
    day_of_week,
    is_weekend,
    month_num,
    month_name,
    year_num
FROM stg_daily_csv
WHERE date_iso <> 'Date_ISO';   -- drop the CSV header row

-- Hourly table: Parquet
INSERT OVERWRITE TABLE hourly_energy_consumption
SELECT
    date_iso,
    hour_of_day,
    energy_kwh,
    avg_power_kw,
    avg_voltage_v,
    sub_metering_1_kwh,
    sub_metering_2_kwh,
    sub_metering_3_kwh,
    sub_remainder_kwh,
    reading_count
FROM stg_hourly_csv
WHERE date_iso <> 'Date_ISO';   -- drop the CSV header row
