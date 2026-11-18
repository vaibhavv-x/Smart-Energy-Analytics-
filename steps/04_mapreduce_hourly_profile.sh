#!/bin/bash
# STEP 4: MapReduce job 2, hour-of-day load profile.
#   Map    : every line -> (hour of the day, energy in kWh, power in kW)
#   Reduce : for each of the 24 hours, total energy, number of readings, average power, highest power
# Shows when in the day the house uses the most electricity.
source "$(dirname "$0")/env.sh"
need_hadoop
title "Step 4: MapReduce job 2, hour-of-day load profile"
mr_job "smart-energy-hourly-profile" mapper_hourly.py reducer_hourly.py /smart-energy/mapreduce/hourly_profile hadoop/mapreduce_yarn_hourly_output.txt
echo; info "All 24 hours (hour, total kWh, readings, average kW, highest kW):"
column -t hadoop/mapreduce_yarn_hourly_output.txt
ok "Next:  bash steps/05_hive_build_tables.sh"
