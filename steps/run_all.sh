#!/bin/bash
# Runs steps 0 to 8 and 10 one after another (about 20 minutes), then leaves the cluster running.
# Start the dashboard afterwards with  bash steps/09_dashboard.sh
cd "$(dirname "$0")" || exit 1
for s in 00_check_setup 01_start_cluster 02_load_data_into_hdfs 03_mapreduce_daily_totals 04_mapreduce_hourly_profile \
         05_hive_build_tables 06_hive_run_queries 07_r_forecast 08_r_graphs 10_tests; do
  bash "$s.sh" || exit 1
done
printf '\n\033[1;32mAll steps finished.\033[0m Dashboard:  bash steps/09_dashboard.sh    Stop:  bash steps/11_stop_everything.sh\n'
