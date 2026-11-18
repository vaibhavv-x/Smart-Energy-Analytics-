#!/bin/bash
# STEP 2: put the dataset into HDFS (Hadoop's file system), from scratch.
# Deletes the old copy and the old MapReduce outputs in HDFS, then uploads the 126.8 MB file again.
# See it in the browser: http://127.0.0.1:9870 > Utilities > Browse the file system > /smart-energy/raw
source "$(dirname "$0")/env.sh"
need_hadoop
title "Step 2: load the dataset into HDFS"
[ -s data/raw/household_power_consumption.txt ] || die "Dataset not found in data/raw/. Run  bash run_on_mac.sh  once to download it."

info "Removing the old copy and old MapReduce outputs ..."
hdfs dfs -rm -r -f -skipTrash /smart-energy/raw /smart-energy/mapreduce 2>/dev/null
info "Creating the folders ..."
hdfs dfs -mkdir -p /smart-energy/raw /smart-energy/mapreduce
info "Uploading data/raw/household_power_consumption.txt (126.8 MB) ..."
hdfs dfs -put -f data/raw/household_power_consumption.txt /smart-energy/raw/

echo; info "The file in HDFS:"
hdfs dfs -ls -h /smart-energy/raw
echo; info "Its first 5 lines:"
hdfs dfs -cat "$RAW_HDFS" 2>/dev/null | head -5
echo; info "How HDFS stores it (blocks and copies):"
hdfs fsck "$RAW_HDFS" 2>/dev/null | grep -E "Total size|Total blocks|Status"
ok "Dataset is in HDFS. Next:  bash steps/03_mapreduce_daily_totals.sh"
