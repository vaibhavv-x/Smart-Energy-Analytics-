-- =============================================================================
-- Feature engineering in Hive for next-day forecasting (the models are trained in R).
-- Every feature uses only earlier days: LAG looks back, and each rolling window ends
-- on the previous day (ROWS BETWEEN n PRECEDING AND 1 PRECEDING), so nothing from the
-- day being predicted leaks into its features.
-- =============================================================================

USE smart_energy_db;

DROP TABLE IF EXISTS daily_features;
CREATE TABLE daily_features STORED AS ORC AS
SELECT *
FROM (
    SELECT
        consumption_date,
        total_energy_kwh AS energy_kwh,
        LAG(total_energy_kwh, 1) OVER (ORDER BY consumption_date) AS lag_1_energy_kwh,
        LAG(total_energy_kwh, 2) OVER (ORDER BY consumption_date) AS lag_2_energy_kwh,
        LAG(total_energy_kwh, 7) OVER (ORDER BY consumption_date) AS lag_7_energy_kwh,
        AVG(total_energy_kwh) OVER (ORDER BY consumption_date ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING) AS rolling_mean_7_kwh,
        STDDEV_SAMP(total_energy_kwh) OVER (ORDER BY consumption_date ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING) AS rolling_std_7_kwh,
        AVG(total_energy_kwh) OVER (ORDER BY consumption_date ROWS BETWEEN 14 PRECEDING AND 1 PRECEDING) AS rolling_mean_14_kwh,
        LAG(avg_power_kw, 1) OVER (ORDER BY consumption_date) AS lag_1_avg_power_kw,
        LAG(max_power_kw, 1) OVER (ORDER BY consumption_date) AS lag_1_max_power_kw,
        LAG(avg_voltage_v, 1) OVER (ORDER BY consumption_date) AS lag_1_avg_voltage_v,
        LAG(sub_metering_1_kwh, 1) OVER (ORDER BY consumption_date) AS lag_1_sub1_kwh,
        LAG(sub_metering_2_kwh, 1) OVER (ORDER BY consumption_date) AS lag_1_sub2_kwh,
        LAG(sub_metering_3_kwh, 1) OVER (ORDER BY consumption_date) AS lag_1_sub3_kwh,
        pmod(dayofweek(consumption_date) + 5, 7) AS day_of_week_num,
        is_weekend,
        month_num,
        year_num
    FROM daily_energy_consumption
    WHERE is_valid_day = 1
) f
WHERE lag_7_energy_kwh IS NOT NULL;
