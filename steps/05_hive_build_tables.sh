#!/bin/bash
# STEP 5: Hive builds its tables from the raw data in HDFS (preprocessing) and the forecasting features.
#   hive/schema.hql        creates the database and 3 tables (raw, daily, hourly)
#   hive/build_tables.hql  cleans the raw rows and fills the daily table (ORC, one folder per year)
#                          and the hourly table (Parquet)
#   hive/features.hql      builds the forecasting inputs with window functions (LAG, rolling averages)
# Every step runs as MapReduce jobs on YARN. Takes about 2 to 3 minutes.
source "$(dirname "$0")/env.sh"
need_hive
title "Step 5: Hive preprocessing and features"
python3 hive/run_hive_on_cluster.py --build-only || die "Hive build failed. See $BD/hiveserver2.log"
echo; info "Tables now in Hive:"
beeline -u "$HIVE_URL" -n "$USER" --silent=true --outputformat=table -e "SHOW TABLES;" 2>/dev/null
info "The daily table is split into one folder (partition) per year:"
beeline -u "$HIVE_URL" -n "$USER" --silent=true --outputformat=table -e "SHOW PARTITIONS daily_energy_consumption;" 2>/dev/null
ok "Next:  bash steps/06_hive_run_queries.sh"
