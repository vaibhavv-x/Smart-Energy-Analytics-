#!/bin/bash
# STEP 1: start the single-node cluster.
#   HDFS  = NameNode (keeps the list of files) + DataNode (stores the file blocks)
#   YARN  = ResourceManager (hands out memory and CPU) + NodeManager (runs the tasks)
#   Hive  = HiveServer2 (accepts SQL queries and turns them into MapReduce jobs)
# Takes 1 to 5 minutes. Web pages: http://127.0.0.1:9870 (HDFS), http://127.0.0.1:8088 (YARN), http://127.0.0.1:10002 (Hive)
source "$(dirname "$0")/env.sh"
title "Step 1: start HDFS, YARN and Hive"

start() {   # start <command> <daemon> <name shown by jps>
  if "$JAVA_HOME/bin/jps" | grep -q " $3$"; then ok "$3 already running"; return; fi
  "$HADOOP_HOME/bin/$1" --daemon start "$2"
  for i in $(seq 1 30); do "$JAVA_HOME/bin/jps" | grep -q " $3$" && { ok "$3 started"; return; }; sleep 1; done
  die "$3 did not start. See $HADOOP_HOME/logs/"
}

info "Starting the two HDFS programs ..."
start hdfs namenode NameNode
start hdfs datanode DataNode
info "Starting the two YARN programs ..."
start yarn resourcemanager ResourceManager
start yarn nodemanager NodeManager

info "Waiting for HDFS to finish its start-up checks (safe mode) ..."
for i in $(seq 1 90); do
  hdfs dfsadmin -safemode get 2>/dev/null | grep -q OFF && yarn node -list 2>/dev/null | grep -q RUNNING && break
  sleep 2
done
hdfs dfsadmin -safemode get 2>/dev/null | grep -q OFF || die "HDFS did not leave safe mode. Run this step again."
ok "HDFS and YARN are ready"

if hive_up; then
  ok "HiveServer2 already running"
else
  info "Starting HiveServer2 (the slowest part, up to 3 minutes) ..."
  hdfs dfs -mkdir -p /tmp/hive >/dev/null 2>&1; hdfs dfs -chmod -R 777 /tmp >/dev/null 2>&1
  ( cd "$BD" && HADOOP_HEAPSIZE=1024 nohup "$HIVE_HOME/bin/hive" --service hiveserver2 >"$BD/hiveserver2.log" 2>&1 < /dev/null & echo $! >"$BD/hiveserver2.pid" )
  for i in $(seq 1 150); do hive_up && break; sleep 2; done
  hive_up || die "HiveServer2 did not start. Last lines of $BD/hiveserver2.log:
$(tail -15 "$BD/hiveserver2.log")"
  ok "HiveServer2 started"
fi

echo
"$JAVA_HOME/bin/jps" | grep -v Jps | sed 's/RunJar/RunJar (HiveServer2)/'
echo
echo "HDFS page   http://127.0.0.1:9870"
echo "YARN page   http://127.0.0.1:8088"
echo "Hive page   http://127.0.0.1:10002"
ok "Cluster is running. Next:  bash steps/02_load_data_into_hdfs.sh"
