#!/bin/bash
# STEP 3: MapReduce job 1, daily energy totals.
#   Map    : every line of the raw file -> (date, energy of that minute in kWh, 1)
#   Shuffle: Hadoop sorts and groups everything by date
#   Reduce : for each date, add up the energy and count the readings
# Result: 1,433 lines "date  total kWh  number of readings". Watch it on http://127.0.0.1:8088
source "$(dirname "$0")/env.sh"
need_hadoop
title "Step 3: MapReduce job 1, daily energy totals"
mr_job "smart-energy-daily-consumption" mapper.py reducer.py /smart-energy/mapreduce/daily_consumption hadoop/mapreduce_yarn_daily_output.txt
echo; info "First 5 result lines (date, kWh, readings). Hadoop sorts the dates as text, so 1/1/2007 comes first:"
head -5 hadoop/mapreduce_yarn_daily_output.txt
ok "Next:  bash steps/04_mapreduce_hourly_profile.sh"
