#!/bin/bash
# STEP 0: check that everything the project needs is installed on this Mac.
# Changes nothing. If something is missing, run  bash run_on_mac.sh  once to install it.
source "$(dirname "$0")/env.sh"
title "Step 0: check the setup"
info "Checks Java, Hadoop, Hive, R, Python and the dataset. Nothing is changed."

missing=0
check() { if eval "$2" >/dev/null 2>&1; then ok "$1"; else printf '\033[1;31m[MISSING]\033[0m %s\n' "$1"; missing=1; fi; }
check "Java 11            ($JAVA_HOME)"             '[ -x "$JAVA_HOME/bin/java" ]'
check "Hadoop 3.3.6       ($HADOOP_HOME)"           '[ -x "$HADOOP_HOME/bin/hdfs" ]'
check "Hive 4.0.1         ($HIVE_HOME)"             '[ -x "$HIVE_HOME/bin/beeline" ]'
check "Hive metastore     ($BD/hive_metastore_db)"  '[ -d "$BD/hive_metastore_db" ]'
check "R                  ($(command -v Rscript))"  'command -v Rscript'
check "R packages         (randomForest, shiny)"    'Rscript -e "stopifnot(requireNamespace(\"randomForest\", quietly=TRUE), requireNamespace(\"shiny\", quietly=TRUE))"'
check "Python 3           ($(command -v python3))"  'command -v python3'
check "Dataset            (data/raw/household_power_consumption.txt)" '[ -s data/raw/household_power_consumption.txt ]'

echo
if [ $missing = 1 ]; then
  die "Something is missing. Run  bash run_on_mac.sh  once (it installs everything), then come back here."
fi
ok "Everything is installed. Next:  bash steps/01_start_cluster.sh"
