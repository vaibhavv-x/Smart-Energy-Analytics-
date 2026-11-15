-- =============================================================================
-- Preprocessing in Hive: build the daily and hourly tables from the raw table.
-- Each INSERT runs as MapReduce jobs on YARN over all 2,075,259 raw rows.
--
-- Rules:
--   * rows with a missing active-power reading ('?') are dropped, never filled in
--   * power to energy: kW / 60 = kWh for a one-minute reading
--   * sub-meters: watt-hours / 1000 = kWh
--   * remainder: energy not covered by the three sub-meters (never below zero)
--   * a day is valid when at least 85% of its 1,440 readings are present (1,224)
-- =============================================================================

USE smart_energy_db;

SET hive.exec.dynamic.partition=true;
SET hive.exec.dynamic.partition.mode=nonstrict;

-- Daily table (ORC, one partition per year)
INSERT OVERWRITE TABLE daily_energy_consumption PARTITION (year_num)
SELECT
    d,
    total_energy_kwh,
    avg_power_kw,
    max_power_kw,
    min_power_kw,
    avg_voltage_v,
    sub_metering_1_kwh,
    sub_metering_2_kwh,
    sub_metering_3_kwh,
    sub_remainder_kwh,
    reading_count,
    reading_count / 1440.0,
    CASE WHEN reading_count >= 1224 THEN 1 ELSE 0 END,
    date_format(d, 'EEEE'),
    CASE WHEN dayofweek(d) IN (1, 7) THEN 1 ELSE 0 END,
    month(d),
    date_format(d, 'MMMM'),
    year(d)
FROM (
    SELECT
        d,
        SUM(kwh) AS total_energy_kwh,
        AVG(power_kw) AS avg_power_kw,
        MAX(power_kw) AS max_power_kw,
        MIN(power_kw) AS min_power_kw,
        AVG(voltage) AS avg_voltage_v,
        SUM(sub1_kwh) AS sub_metering_1_kwh,
        SUM(sub2_kwh) AS sub_metering_2_kwh,
        SUM(sub3_kwh) AS sub_metering_3_kwh,
        SUM(remainder_kwh) AS sub_remainder_kwh,
        CAST(COUNT(*) AS INT) AS reading_count
    FROM (
        SELECT
            concat(split(record_date, '/')[2], '-',
                   lpad(split(record_date, '/')[1], 2, '0'), '-',
                   lpad(split(record_date, '/')[0], 2, '0')) AS d,
            global_active_power AS power_kw,
            global_active_power / 60.0 AS kwh,
            voltage,
            sub_metering_1 / 1000.0 AS sub1_kwh,
            sub_metering_2 / 1000.0 AS sub2_kwh,
            sub_metering_3 / 1000.0 AS sub3_kwh,
            greatest(global_active_power / 60.0
                     - (sub_metering_1 + sub_metering_2 + sub_metering_3) / 1000.0, 0.0) AS remainder_kwh
        FROM raw_household_power
        WHERE record_date <> 'Date' AND global_active_power IS NOT NULL
    ) readings
    GROUP BY d
) days;

-- Hourly table (Parquet)
INSERT OVERWRITE TABLE hourly_energy_consumption
SELECT
    d,
    hour_of_day,
    SUM(kwh),
    AVG(power_kw),
    AVG(voltage),
    SUM(sub1_kwh),
    SUM(sub2_kwh),
    SUM(sub3_kwh),
    SUM(remainder_kwh),
    CAST(COUNT(*) AS INT)
FROM (
    SELECT
        concat(split(record_date, '/')[2], '-',
               lpad(split(record_date, '/')[1], 2, '0'), '-',
               lpad(split(record_date, '/')[0], 2, '0')) AS d,
        CAST(split(record_time, ':')[0] AS INT) AS hour_of_day,
        global_active_power AS power_kw,
        global_active_power / 60.0 AS kwh,
        voltage,
        sub_metering_1 / 1000.0 AS sub1_kwh,
        sub_metering_2 / 1000.0 AS sub2_kwh,
        sub_metering_3 / 1000.0 AS sub3_kwh,
        greatest(global_active_power / 60.0
                 - (sub_metering_1 + sub_metering_2 + sub_metering_3) / 1000.0, 0.0) AS remainder_kwh
    FROM raw_household_power
    WHERE record_date <> 'Date' AND global_active_power IS NOT NULL
) readings
GROUP BY d, hour_of_day;
