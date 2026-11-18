#!/bin/bash
# Shared settings for the step scripts. Each step loads this file first; you never run it on its own.

STEPS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$(dirname "$STEPS")"
BD="$HOME/bigdata"
export JAVA_HOME="$(ls -d "$BD"/jdk-11*/Contents/Home 2>/dev/null | head -1)"
export HADOOP_HOME="$BD/hadoop-3.3.6"
export HADOOP_CONF_DIR="$HADOOP_HOME/etc/hadoop"
export HIVE_HOME="$BD/apache-hive-4.0.1-bin"
export PATH="$JAVA_HOME/bin:$HADOOP_HOME/bin:$HIVE_HOME/bin:$PATH"
cd "$PROJECT" || exit 1

RAW_HDFS="/smart-energy/raw/household_power_consumption.txt"
HIVE_URL="jdbc:hive2://localhost:10000/smart_energy_db"

title() { printf '\n\033[1;36m==== %s ====\033[0m\n' "$1"; }
info()  { printf '\033[2m%s\033[0m\n' "$1"; }
ok()    { printf '\033[1;32m[ OK ]\033[0m %s\n' "$1"; }
die()   { printf '\n\033[1;31m[STOP]\033[0m %s\n' "$1"; exit 1; }

hadoop_up() { "$JAVA_HOME/bin/jps" 2>/dev/null | grep -q " NameNode$"; }
hive_up()   { nc -z localhost 10000 >/dev/null 2>&1; }
need_hadoop() { hadoop_up || die "Hadoop is not running. Run  bash steps/01_start_cluster.sh  first."; }
need_hive()   { hive_up || die "Hive is not running. Run  bash steps/01_start_cluster.sh  first (Hive starts last; give it a minute)."; }

source "$STEPS/mr_job.sh"   # defines mr_job, used by steps 3 and 4
