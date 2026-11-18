#!/bin/bash
# STEP 11: switch everything off: the dashboard, HiveServer2 and the four Hadoop programs.
# The data stays in HDFS and Hive for next time.
source "$(dirname "$0")/env.sh"
title "Step 11: stop everything"
pkill -f "shiny::runApp" 2>/dev/null && ok "Dashboard stopped" || info "Dashboard was not running"
if hive_up; then
  [ -f "$BD/hiveserver2.pid" ] && kill "$(cat "$BD/hiveserver2.pid")" 2>/dev/null
  pkill -f "org.apache.hive.service.server.HiveServer2" 2>/dev/null
  rm -f "$BD/hiveserver2.pid"; ok "HiveServer2 stopped"
else
  info "HiveServer2 was not running"
fi
for d in "yarn nodemanager" "yarn resourcemanager" "hdfs datanode" "hdfs namenode"; do
  set -- $d; "$HADOOP_HOME/bin/$1" --daemon stop "$2" 2>/dev/null
done
sleep 2
left=$("$JAVA_HOME/bin/jps" | grep -v Jps | wc -l | tr -d ' ')
[ "$left" = 0 ] && ok "Hadoop stopped. Everything is off." || info "Still running: $("$JAVA_HOME/bin/jps" | grep -v Jps | tr '\n' ' ')"
