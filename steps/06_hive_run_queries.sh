#!/bin/bash
# STEP 6: run the 12 analysis queries (hive/queries.hql) on Hive and save each result.
# Prints the first rows of every result. Results go to hive/cluster_results/q01.csv ... q12.csv,
# and the forecasting features to hive/cluster_results/daily_features.csv (used by R in step 7).
# Each query becomes MapReduce jobs on YARN, so this takes about 8 to 10 minutes.
source "$(dirname "$0")/env.sh"
need_hive
title "Step 6: the 12 Hive queries"
python3 hive/run_hive_on_cluster.py --queries-only --show 5 || die "A Hive query failed. See $BD/hiveserver2.log"
ok "All results saved in hive/cluster_results/. Next:  bash steps/07_r_forecast.sh"
