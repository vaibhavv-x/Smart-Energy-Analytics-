#!/bin/bash
# ==============================================================================
# Smart Energy Analytics (Batch 30): one-command setup and run for macOS
#
# Tools: Hadoop HDFS + MapReduce (YARN), Apache Hive, R.   No Spark is used.
#
# Stages (every stage is safe to re-run; finished installs are skipped):
#   1. Java 11      downloads Temurin JDK 11 into ~/bigdata
#   2. Hadoop       downloads Hadoop 3.3.6 into ~/bigdata and configures a single-node cluster
#   3. Dataset      downloads the UCI household power dataset (2,075,259 rows) into data/raw
#   4. Cluster      formats HDFS (first run only) and starts NameNode, DataNode, YARN
#   5. HDFS         creates /smart-energy and loads the full dataset
#   6. MapReduce    two Hadoop Streaming jobs on YARN: daily energy totals, hour-of-day load profile
#   7. Hive         downloads Hive 4.0.1, starts HiveServer2, builds the tables from the raw data
#                   (preprocessing), builds the feature table, runs the 12 queries on YARN
#   8. R            trains the forecasting models and draws the graphs (needs R; installed with
#                   Homebrew if it is missing)
#   9. Tests        runs the automated checks
#
# Usage (from the project folder, in Terminal):
#   bash run_on_mac.sh            run everything
#   bash run_on_mac.sh start      only start HDFS, YARN and HiveServer2 (no jobs)
#   bash run_on_mac.sh hive       run only the Hive stage
#   bash run_on_mac.sh r          run only the R stage (models and graphs)
#   bash run_on_mac.sh test       run only the tests
#   bash run_on_mac.sh status     show running daemons and HDFS contents
#   bash run_on_mac.sh stop       stop HiveServer2 and the Hadoop daemons
#
# Everything it installs lives in ~/bigdata (about 3 GB), except R (Homebrew).
# ==============================================================================

PROJECT="$(cd "$(dirname "$0")" && pwd)"
BD="$HOME/bigdata"
HADOOP_VERSION="3.3.6"
export HADOOP_HOME="$BD/hadoop-$HADOOP_VERSION"
export HADOOP_CONF_DIR="$HADOOP_HOME/etc/hadoop"
VENV="$BD/venv"
DATASET_DIR="$BD/dataset"
RAW_NAME="household_power_consumption.txt"
HDFS_RAW="/smart-energy/raw/$RAW_NAME"
HDFS_OUT="/smart-energy/mapreduce/daily_consumption"
HDFS_OUT_HOURLY="/smart-energy/mapreduce/hourly_profile"
HIVE_VERSION="4.0.1"
export HIVE_HOME="$BD/apache-hive-$HIVE_VERSION-bin"

say()  { printf '\n\033[1m=== %s ===\033[0m\n' "$1"; }
ok()   { printf '[ OK ] %s\n' "$1"; }
die()  { printf '\n[STOP] %s\n' "$1"; exit 1; }

mkdir -p "$BD" || die "Cannot create $BD"

# ------------------------------------------------------------------------------ Java
setup_java() {
  say "1. Java 11"
  local found=""
  if [ -x /usr/libexec/java_home ]; then
    found="$(/usr/libexec/java_home -v 11 2>/dev/null | head -1)"
    case "$found" in *11*) ;; *) found="" ;; esac
  fi
  if [ -z "$found" ]; then
    found="$(ls -d "$BD"/jdk-11*/Contents/Home 2>/dev/null | head -1)"
  fi
  if [ -z "$found" ]; then
    local arch="x64"
    [ "$(uname -m)" = "arm64" ] && arch="aarch64"
    echo "Downloading Temurin JDK 11 ($arch), about 190 MB ..."
    curl -fL --retry 3 -o "$BD/jdk11.tar.gz" \
      "https://api.adoptium.net/v3/binary/latest/11/ga/mac/$arch/jdk/hotspot/normal/eclipse" \
      || die "JDK download failed. Check the internet connection and run the script again."
    tar -xzf "$BD/jdk11.tar.gz" -C "$BD" || die "Could not unpack the JDK. Delete $BD/jdk11.tar.gz and run again."
    rm -f "$BD/jdk11.tar.gz"
    found="$(ls -d "$BD"/jdk-11*/Contents/Home 2>/dev/null | head -1)"
  fi
  [ -x "$found/bin/java" ] || die "No working JDK 11 found."
  export JAVA_HOME="$found"
  export PATH="$JAVA_HOME/bin:$HADOOP_HOME/bin:$HADOOP_HOME/sbin:$PATH"
  ok "JAVA_HOME=$JAVA_HOME"
}

# ------------------------------------------------------------------------------ Hadoop
write_conf() {
  local data="$BD/hadoop_data"
  mkdir -p "$data"
  cat > "$HADOOP_CONF_DIR/core-site.xml" <<XML
<?xml version="1.0"?>
<configuration>
  <property><name>fs.defaultFS</name><value>hdfs://localhost:9000</value></property>
  <property><name>hadoop.tmp.dir</name><value>$data/tmp</value></property>
</configuration>
XML
  cat > "$HADOOP_CONF_DIR/hdfs-site.xml" <<XML
<?xml version="1.0"?>
<configuration>
  <property><name>dfs.replication</name><value>1</value></property>
  <property><name>dfs.namenode.name.dir</name><value>file://$data/namenode</value></property>
  <property><name>dfs.datanode.data.dir</name><value>file://$data/datanode</value></property>
  <!-- Listen on this machine only: HDFS has no login, so it must not be reachable from the network. -->
  <property><name>dfs.namenode.http-address</name><value>127.0.0.1:9870</value></property>
  <property><name>dfs.datanode.address</name><value>127.0.0.1:9866</value></property>
  <property><name>dfs.datanode.http.address</name><value>127.0.0.1:9864</value></property>
  <property><name>dfs.datanode.ipc.address</name><value>127.0.0.1:9867</value></property>
</configuration>
XML
  cat > "$HADOOP_CONF_DIR/mapred-site.xml" <<XML
<?xml version="1.0"?>
<configuration>
  <property><name>mapreduce.framework.name</name><value>yarn</value></property>
  <property><name>yarn.app.mapreduce.am.env</name><value>HADOOP_MAPRED_HOME=$HADOOP_HOME</value></property>
  <property><name>mapreduce.map.env</name><value>HADOOP_MAPRED_HOME=$HADOOP_HOME</value></property>
  <property><name>mapreduce.reduce.env</name><value>HADOOP_MAPRED_HOME=$HADOOP_HOME</value></property>
  <property><name>yarn.app.mapreduce.am.resource.mb</name><value>512</value></property>
  <property><name>mapreduce.map.memory.mb</name><value>512</value></property>
  <property><name>mapreduce.reduce.memory.mb</name><value>512</value></property>
</configuration>
XML
  cat > "$HADOOP_CONF_DIR/yarn-site.xml" <<XML
<?xml version="1.0"?>
<configuration>
  <property><name>yarn.resourcemanager.hostname</name><value>localhost</value></property>
  <property><name>yarn.nodemanager.hostname</name><value>localhost</value></property>
  <property><name>yarn.nodemanager.aux-services</name><value>mapreduce_shuffle</value></property>
  <property><name>yarn.nodemanager.env-whitelist</name><value>JAVA_HOME,HADOOP_COMMON_HOME,HADOOP_HDFS_HOME,HADOOP_CONF_DIR,CLASSPATH_PREPEND_DISTCACHE,HADOOP_YARN_HOME,HADOOP_HOME,HADOOP_MAPRED_HOME,PATH,LANG,TZ</value></property>
  <property><name>yarn.nodemanager.resource.memory-mb</name><value>4096</value></property>
  <property><name>yarn.scheduler.minimum-allocation-mb</name><value>256</value></property>
  <property><name>yarn.scheduler.maximum-allocation-mb</name><value>4096</value></property>
  <property><name>yarn.nodemanager.vmem-check-enabled</name><value>false</value></property>
  <property><name>yarn.nodemanager.pmem-check-enabled</name><value>false</value></property>
  <property><name>yarn.nodemanager.disk-health-checker.max-disk-utilization-per-disk-percentage</name><value>98.5</value></property>
</configuration>
XML
  if ! grep -q "smart-energy settings" "$HADOOP_CONF_DIR/hadoop-env.sh" 2>/dev/null; then
    cat >> "$HADOOP_CONF_DIR/hadoop-env.sh" <<ENV

# --- smart-energy settings ---
export JAVA_HOME="$JAVA_HOME"
export HADOOP_OPTS="\$HADOOP_OPTS -Djava.net.preferIPv4Stack=true"
ENV
  fi
}

setup_hadoop() {
  say "2. Hadoop $HADOOP_VERSION"
  if [ ! -x "$HADOOP_HOME/bin/hdfs" ]; then
    local tgz="$BD/hadoop-$HADOOP_VERSION.tar.gz"
    echo "Downloading Hadoop $HADOOP_VERSION, about 700 MB. This is the slow step ..."
    curl -fL --retry 3 -C - -o "$tgz" "https://dlcdn.apache.org/hadoop/common/hadoop-$HADOOP_VERSION/hadoop-$HADOOP_VERSION.tar.gz" \
      || curl -fL --retry 3 -C - -o "$tgz" "https://archive.apache.org/dist/hadoop/common/hadoop-$HADOOP_VERSION/hadoop-$HADOOP_VERSION.tar.gz" \
      || die "Hadoop download failed. Run the script again; the download resumes where it stopped."
    echo "Unpacking ..."
    tar -xzf "$tgz" -C "$BD" || { rm -f "$tgz"; die "The Hadoop archive was incomplete and has been deleted. Run the script again."; }
    rm -f "$tgz"
  fi
  [ -x "$HADOOP_HOME/bin/hdfs" ] || die "Hadoop is not in $HADOOP_HOME"
  write_conf
  ok "Hadoop ready in $HADOOP_HOME"
}

# ------------------------------------------------------------------------------ Dataset
setup_dataset() {
  say "3. Dataset (UCI Individual Household Electric Power Consumption)"
  mkdir -p "$DATASET_DIR" "$PROJECT/data/raw"
  if [ ! -s "$DATASET_DIR/$RAW_NAME" ]; then
    if [ -s "$PROJECT/data/raw/$RAW_NAME" ]; then
      cp "$PROJECT/data/raw/$RAW_NAME" "$DATASET_DIR/$RAW_NAME"
    else
      echo "Downloading the dataset, about 20 MB zipped ..."
      curl -fL --retry 3 -o "$DATASET_DIR/uci.zip" \
        "https://archive.ics.uci.edu/static/public/235/individual+household+electric+power+consumption.zip" \
        || die "Dataset download failed. Download it by hand from https://archive.ics.uci.edu/dataset/235 , unzip it, put $RAW_NAME in data/raw and run again."
      unzip -o -q "$DATASET_DIR/uci.zip" -d "$DATASET_DIR" || die "Could not unzip the dataset."
      rm -f "$DATASET_DIR/uci.zip"
    fi
  fi
  [ -s "$DATASET_DIR/$RAW_NAME" ] || die "$RAW_NAME not found after download."
  [ -s "$PROJECT/data/raw/$RAW_NAME" ] || cp "$DATASET_DIR/$RAW_NAME" "$PROJECT/data/raw/$RAW_NAME"
  ok "$(wc -l < "$DATASET_DIR/$RAW_NAME" | tr -d ' ') lines in $RAW_NAME"
}

# ------------------------------------------------------------------------------ Cluster
running() { "$JAVA_HOME/bin/jps" 2>/dev/null | grep -q " $1\$"; }

start_daemon() {   # start_daemon <command> <daemon> <jps name>
  if running "$3"; then ok "$3 already running"; return; fi
  "$HADOOP_HOME/bin/$1" --daemon start "$2" >/dev/null 2>&1
  local i=0
  while [ $i -lt 30 ]; do running "$3" && { ok "$3 started"; return; }; sleep 1; i=$((i + 1)); done
  echo "Last lines of the $2 log:"; tail -25 "$HADOOP_HOME"/logs/*-"$2"-*.log 2>/dev/null
  die "$3 did not start. Send the log lines above to get it fixed."
}

start_cluster() {
  say "4. Start the single-node cluster"
  if [ ! -d "$BD/hadoop_data/namenode/current" ]; then
    echo "Formatting HDFS (first run only) ..."
    "$HADOOP_HOME/bin/hdfs" namenode -format -nonInteractive >"$BD/format.log" 2>&1 \
      || { tail -20 "$BD/format.log"; die "NameNode format failed."; }
  fi
  start_daemon hdfs namenode NameNode
  start_daemon hdfs datanode DataNode
  start_daemon yarn resourcemanager ResourceManager
  start_daemon yarn nodemanager NodeManager

  echo "Waiting for HDFS to leave safe mode and for the DataNode and NodeManager to register ..."
  local i=0
  while [ $i -lt 90 ]; do
    if "$HADOOP_HOME/bin/hdfs" dfsadmin -safemode get 2>/dev/null | grep -q "OFF" \
       && "$HADOOP_HOME/bin/hdfs" dfsadmin -report 2>/dev/null | grep -q "Live datanodes (1)" \
       && "$HADOOP_HOME/bin/yarn" node -list 2>/dev/null | grep -q "RUNNING"; then
      ok "HDFS and YARN are up.  NameNode UI: http://localhost:9870   YARN UI: http://localhost:8088"
      return
    fi
    sleep 2; i=$((i + 1))
  done
  "$HADOOP_HOME/bin/hdfs" dfsadmin -report 2>&1 | head -20
  "$HADOOP_HOME/bin/yarn" node -list -all 2>&1 | tail -5
  die "The cluster did not become ready in 3 minutes. Send the lines above to get it fixed."
}

# ------------------------------------------------------------------------------ HDFS + MapReduce
load_hdfs() {
  say "5. Load the dataset into HDFS"
  local h="$HADOOP_HOME/bin/hdfs"
  "$h" dfs -mkdir -p /smart-energy/raw /smart-energy/cleaned /smart-energy/mapreduce /smart-energy/hive/warehouse \
    || die "Could not create the HDFS folders."
  "$h" dfs -put -f "$DATASET_DIR/$RAW_NAME" "$HDFS_RAW" || die "Could not copy the dataset into HDFS."
  "$h" dfs -ls -h /smart-energy/raw
  "$h" fsck "$HDFS_RAW" -files -blocks 2>/dev/null | grep -E "Total blocks|Status|bytes," | head -4
  ok "Dataset is in HDFS at $HDFS_RAW"
}

mr_job() {   # mr_job <job name> <mapper> <reducer> <HDFS output dir> <local result file>
  local jar job="$BD/job" py
  jar="$(ls "$HADOOP_HOME"/share/hadoop/tools/lib/hadoop-streaming-*.jar | head -1)"
  py="$(command -v python3)"
  mkdir -p "$job"                      # copied here because -files cannot take a path with a space in it
  cp "$PROJECT/hadoop/$2" "$PROJECT/hadoop/$3" "$job/"
  "$HADOOP_HOME/bin/hdfs" dfs -rm -r -f "$4" >/dev/null 2>&1
  local start; start=$(date +%s)
  "$HADOOP_HOME/bin/hadoop" jar "$jar" \
    -D mapreduce.job.name="$1" \
    -D mapreduce.job.reduces=1 \
    -files "$job/$2,$job/$3" \
    -mapper "$py $2" -reducer "$py $3" \
    -input "$HDFS_RAW" -output "$4" 2>&1 | tee "$BD/$1.log" \
    | grep -E "Running job|map [0-9]+% reduce|completed successfully|Map input records|Reduce output records|Launched map tasks|Launched reduce tasks|ERROR|FAILED|Exception"
  "$HADOOP_HOME/bin/hdfs" dfs -test -e "$4/_SUCCESS" \
    || { tail -30 "$BD/$1.log"; die "The MapReduce job $1 failed. Send the lines above (full log: $BD/$1.log)."; }
  "$HADOOP_HOME/bin/hdfs" dfs -cat "$4/part-*" > "$PROJECT/hadoop/$5"
  ok "$1 finished in $(( $(date +%s) - start )) s: $(wc -l < "$PROJECT/hadoop/$5" | tr -d ' ') rows saved to hadoop/$5"
}

run_mapreduce() {
  say "6. MapReduce on YARN (Hadoop Streaming, full dataset)"
  echo "Job 1 of 2: daily energy totals"
  mr_job "smart-energy-daily-consumption" mapper.py reducer.py "$HDFS_OUT" mapreduce_yarn_daily_output.txt
  cp "$BD/smart-energy-daily-consumption.log" "$PROJECT/hadoop/mapreduce_yarn_job_log.txt"
  echo "Job 2 of 2: hour-of-day load profile"
  mr_job "smart-energy-hourly-profile" mapper_hourly.py reducer_hourly.py "$HDFS_OUT_HOURLY" mapreduce_yarn_hourly_output.txt
  cp "$BD/smart-energy-hourly-profile.log" "$PROJECT/hadoop/mapreduce_yarn_hourly_job_log.txt"
}

# ------------------------------------------------------------------------------ Hive
setup_hive() {
  say "7. Apache Hive $HIVE_VERSION"
  if [ ! -x "$HIVE_HOME/bin/beeline" ]; then
    local tgz="$BD/apache-hive-$HIVE_VERSION-bin.tar.gz" i=0
    echo "Downloading Hive $HIVE_VERSION, about 390 MB ..."
    while [ $i -lt 10 ]; do
      curl -fL -C - --speed-limit 2000 --speed-time 20 -o "$tgz" \
        "https://archive.apache.org/dist/hive/hive-$HIVE_VERSION/apache-hive-$HIVE_VERSION-bin.tar.gz" && break
      i=$((i + 1)); echo "Download interrupted, resuming (attempt $i) ..."
    done
    tar -xzf "$tgz" -C "$BD" || die "Hive download failed. Run the script again; the download resumes where it stopped."
    rm -f "$tgz"
  fi
  mkdir -p "$BD/hive_tmp"
  cat > "$HIVE_HOME/conf/hive-site.xml" <<XML
<?xml version="1.0"?>
<configuration>
  <property><name>javax.jdo.option.ConnectionURL</name><value>jdbc:derby:;databaseName=$BD/hive_metastore_db;create=true</value></property>
  <property><name>hive.metastore.warehouse.dir</name><value>/smart-energy/hive/warehouse</value></property>
  <property><name>hive.execution.engine</name><value>mr</value></property>
  <property><name>hive.server2.enable.doAs</name><value>false</value></property>
  <property><name>hive.server2.thrift.bind.host</name><value>localhost</value></property>
  <property><name>hive.server2.thrift.port</name><value>10000</value></property>
  <property><name>hive.server2.webui.host</name><value>localhost</value></property>
  <property><name>hive.server2.webui.port</name><value>10002</value></property>
  <property><name>hive.exec.dynamic.partition.mode</name><value>nonstrict</value></property>
  <property><name>hive.exec.mode.local.auto</name><value>false</value></property>
  <property><name>hive.auto.convert.join</name><value>false</value></property>
  <property><name>hive.stats.autogather</name><value>false</value></property>
  <property><name>hive.exec.scratchdir</name><value>/tmp/hive</value></property>
  <property><name>hive.exec.local.scratchdir</name><value>$BD/hive_tmp</value></property>
  <property><name>hive.downloaded.resources.dir</name><value>$BD/hive_tmp/resources</value></property>
  <property><name>hive.querylog.location</name><value>$BD/hive_tmp/querylog</value></property>
  <property><name>hive.server2.logging.operation.log.location</name><value>$BD/hive_tmp/operation_logs</value></property>
  <!-- Hive's ORC writer needs protobuf 3; Hadoop ships 2.5, so the job's own jars must come first. -->
  <property><name>mapreduce.job.user.classpath.first</name><value>true</value></property>
</configuration>
XML
  if [ ! -d "$BD/hive_metastore_db" ]; then
    echo "Creating the Hive metastore (first run only) ..."
    ( cd "$BD" && "$HIVE_HOME/bin/schematool" -dbType derby -initSchema >"$BD/hive_schematool.log" 2>&1 ) \
      || { tail -20 "$BD/hive_schematool.log"; die "Could not create the Hive metastore."; }
  fi
  ok "Hive ready in $HIVE_HOME"
}

start_hiveserver2() {
  if nc -z localhost 10000 >/dev/null 2>&1; then ok "HiveServer2 already running"; return; fi
  "$HADOOP_HOME/bin/hdfs" dfs -mkdir -p /tmp/hive /smart-energy/hive/warehouse >/dev/null 2>&1
  "$HADOOP_HOME/bin/hdfs" dfs -chmod -R 777 /tmp >/dev/null 2>&1
  ( cd "$BD" && HADOOP_HEAPSIZE=1024 nohup "$HIVE_HOME/bin/hive" --service hiveserver2 >"$BD/hiveserver2.log" 2>&1 & echo $! >"$BD/hiveserver2.pid" )
  local i=0
  while [ $i -lt 90 ]; do
    nc -z localhost 10000 >/dev/null 2>&1 && { ok "HiveServer2 started (JDBC jdbc:hive2://localhost:10000, web UI http://localhost:10002)"; return; }
    sleep 2; i=$((i + 1))
  done
  tail -25 "$BD/hiveserver2.log"
  die "HiveServer2 did not start. Send the log lines above."
}

stop_hiveserver2() {
  [ -f "$BD/hiveserver2.pid" ] && kill "$(cat "$BD/hiveserver2.pid")" 2>/dev/null
  pkill -f "org.apache.hive.service.server.HiveServer2" 2>/dev/null
  rm -f "$BD/hiveserver2.pid"
}

run_hive() {
  setup_hive
  start_hiveserver2
  echo "Building the tables from the raw data, building the features and running the 12 queries (all MapReduce jobs on YARN, about 12 minutes) ..."
  ( cd "$PROJECT" && python3 -u hive/run_hive_on_cluster.py 2>&1 | tee "$BD/hive_run.log" ) 
  grep -q "queries executed on Hive" "$BD/hive_run.log" || die "The Hive stage failed. Send the lines above (server log: $BD/hiveserver2.log)."
  ok "Hive results saved to hive/cluster_results/ and hive/hive_cluster_report.md"
}

# ------------------------------------------------------------------------------ R
run_r() {
  say "8. R: forecasting models and graphs"
  if ! command -v Rscript >/dev/null 2>&1; then
    command -v brew >/dev/null 2>&1 || die "R is not installed. Install it from https://cran.r-project.org/bin/macosx/ and run again."
    echo "Installing R with Homebrew (a few minutes) ..."
    brew install r || die "Could not install R. Install it from https://cran.r-project.org/bin/macosx/ and run again."
  fi
  Rscript -e 'lib <- Sys.getenv("R_LIBS_USER"); dir.create(lib, recursive = TRUE, showWarnings = FALSE); .libPaths(c(lib, .libPaths())); if (!requireNamespace("randomForest", quietly = TRUE)) install.packages("randomForest", lib = lib, repos = "https://cloud.r-project.org")' \
    >"$BD/r_packages.log" 2>&1 || { tail -15 "$BD/r_packages.log"; die "Could not install the R package randomForest."; }
  ( cd "$PROJECT" && Rscript r/forecast_models.R && Rscript r/visualize.R ) || die "The R stage failed. Send the lines above."
  ok "Model results in r/output/, graphs in graphs/"
}

# ------------------------------------------------------------------------------ Tests
run_tests() {
  say "9. Tests"
  if [ ! -x "$VENV/bin/python" ]; then python3 -m venv "$VENV" || die "Could not create the test environment."; fi
  "$VENV/bin/python" -c "import pytest" 2>/dev/null || "$VENV/bin/python" -m pip install --quiet pytest \
    || die "Could not install pytest. Check the internet connection and run again."
  ( cd "$PROJECT" && "$VENV/bin/python" -m pytest tests -q -p no:cacheprovider ) || die "Some tests failed. Send the lines above."
  ok "All tests passed"
}

# ------------------------------------------------------------------------------ Commands
case "${1:-all}" in
  all)
    free_gb=$(df -g "$HOME" | awk 'NR==2 {print $4}')
    [ "${free_gb:-10}" -ge 4 ] || die "Less than 4 GB free on disk. Free some space first."
    setup_java; setup_hadoop; setup_dataset
    start_cluster; load_hdfs; run_mapreduce; run_hive; run_r; run_tests
    say "Finished"
    echo "HDFS UI       http://localhost:9870   (Utilities > Browse the file system > /smart-energy)"
    echo "YARN UI       http://localhost:8088   (MapReduce and Hive jobs)"
    echo "HiveServer2   http://localhost:10002"
    echo "Graphs        graphs/*.png            Model results  r/output/"
    echo "Stop all      bash run_on_mac.sh stop"
    ;;
  start)
    setup_java; start_cluster; start_hiveserver2
    echo "HDFS UI       http://localhost:9870"
    echo "YARN UI       http://localhost:8088"
    echo "HiveServer2   http://localhost:10002"
    ;;
  hive)
    setup_java; start_cluster; run_hive
    ;;
  r)
    run_r
    ;;
  test)
    run_tests
    ;;
  status)
    setup_java >/dev/null
    "$JAVA_HOME/bin/jps" | grep -v Jps
    "$HADOOP_HOME/bin/hdfs" dfs -ls -R -h /smart-energy 2>/dev/null | grep -v "/hive/warehouse/.*/" | head -30
    ;;
  stop)
    setup_java >/dev/null
    stop_hiveserver2
    "$HADOOP_HOME/bin/yarn" --daemon stop nodemanager
    "$HADOOP_HOME/bin/yarn" --daemon stop resourcemanager
    "$HADOOP_HOME/bin/hdfs" --daemon stop datanode
    "$HADOOP_HOME/bin/hdfs" --daemon stop namenode
    ok "HiveServer2 and the Hadoop daemons stopped"
    ;;
  *) echo "usage: bash run_on_mac.sh [all|start|hive|r|test|status|stop]"; exit 1 ;;
esac
