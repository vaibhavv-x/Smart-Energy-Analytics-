-- =============================================================================
-- Hive schema: Smart Energy Analytics (Batch 30)
-- Database, an external table over the raw file in HDFS, and the two analysis tables.
-- =============================================================================

CREATE DATABASE IF NOT EXISTS smart_energy_db
COMMENT 'Household electricity consumption analytics'
LOCATION '/smart-energy/hive/warehouse';

USE smart_energy_db;

-- 1. Raw one-minute readings: external table over /smart-energy/raw (2,075,259 rows).
--    Missing readings are written as '?' in the file and are read as NULL.
DROP TABLE IF EXISTS raw_household_power;
CREATE EXTERNAL TABLE raw_household_power (
    record_date STRING COMMENT 'Measurement date (d/M/yyyy)',
    record_time STRING COMMENT 'Measurement time (HH:mm:ss)',
    global_active_power DOUBLE COMMENT 'Minute-averaged active power in kW',
    global_reactive_power DOUBLE COMMENT 'Minute-averaged reactive power in kW',
    voltage DOUBLE COMMENT 'Minute-averaged voltage in volts',
    global_intensity DOUBLE COMMENT 'Minute-averaged current in amperes',
    sub_metering_1 DOUBLE COMMENT 'Kitchen, watt-hours',
    sub_metering_2 DOUBLE COMMENT 'Laundry room, watt-hours',
    sub_metering_3 DOUBLE COMMENT 'Water heater and air conditioner, watt-hours'
)
ROW FORMAT DELIMITED
FIELDS TERMINATED BY ';'
STORED AS TEXTFILE
LOCATION '/smart-energy/raw'
TBLPROPERTIES ("serialization.null.format"="?");

-- 2. Daily table: ORC, partitioned by year.
DROP TABLE IF EXISTS daily_energy_consumption;
CREATE TABLE daily_energy_consumption (
    consumption_date STRING COMMENT 'ISO date yyyy-MM-dd',
    total_energy_kwh DOUBLE COMMENT 'Daily energy in kWh',
    avg_power_kw DOUBLE COMMENT 'Average power in kW',
    max_power_kw DOUBLE COMMENT 'Peak power in kW',
    min_power_kw DOUBLE COMMENT 'Lowest power in kW',
    avg_voltage_v DOUBLE COMMENT 'Average voltage in volts',
    sub_metering_1_kwh DOUBLE COMMENT 'Kitchen energy in kWh',
    sub_metering_2_kwh DOUBLE COMMENT 'Laundry energy in kWh',
    sub_metering_3_kwh DOUBLE COMMENT 'Water heater and air conditioner energy in kWh',
    sub_remainder_kwh DOUBLE COMMENT 'Energy not covered by any sub-meter, in kWh',
    reading_count INT COMMENT 'Valid one-minute readings in the day',
    completeness_ratio DOUBLE COMMENT 'reading_count / 1440',
    is_valid_day INT COMMENT '1 if at least 85% of the readings are present',
    day_of_week STRING COMMENT 'Monday..Sunday',
    is_weekend INT COMMENT '1 for Saturday and Sunday',
    month_num INT COMMENT 'Month number 1..12',
    month_name STRING COMMENT 'January..December'
)
PARTITIONED BY (year_num INT)
STORED AS ORC
TBLPROPERTIES ("orc.compress"="SNAPPY");

-- 3. Hourly table: Parquet.
DROP TABLE IF EXISTS hourly_energy_consumption;
CREATE TABLE hourly_energy_consumption (
    consumption_date STRING COMMENT 'ISO date yyyy-MM-dd',
    hour_of_day INT COMMENT 'Hour of the day 0..23',
    total_energy_kwh DOUBLE COMMENT 'Hourly energy in kWh',
    avg_power_kw DOUBLE COMMENT 'Average power in kW',
    avg_voltage_v DOUBLE COMMENT 'Average voltage in volts',
    sub_metering_1_kwh DOUBLE COMMENT 'Kitchen energy in kWh',
    sub_metering_2_kwh DOUBLE COMMENT 'Laundry energy in kWh',
    sub_metering_3_kwh DOUBLE COMMENT 'Water heater and air conditioner energy in kWh',
    sub_remainder_kwh DOUBLE COMMENT 'Energy not covered by any sub-meter, in kWh',
    reading_count INT COMMENT 'Valid one-minute readings in the hour'
)
STORED AS PARQUET;
