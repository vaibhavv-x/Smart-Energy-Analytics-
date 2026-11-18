#!/bin/bash
# Helper used by steps 3 and 4: runs one Hadoop Streaming MapReduce job on YARN.
# Usage: mr_job <job name> <mapper.py> <reducer.py> <HDFS output folder> <local copy of the result>
mr_job() {
  local name="$1" mapper="$2" reducer="$3" out="$4" local_copy="$5"
  local jar job="$BD/job" py
  jar="$(ls "$HADOOP_HOME"/share/hadoop/tools/lib/hadoop-streaming-*.jar | head -1)"
  py="$(command -v python3)"
  mkdir -p "$job"
  cp "hadoop/$mapper" "hadoop/$reducer" "$job/"     # Hadoop cannot read paths with a space ("big data")
  hdfs dfs -rm -r -f -skipTrash "$out" >/dev/null 2>&1

  info "Running: mapper = hadoop/$mapper, reducer = hadoop/$reducer"
  info "Input  : $RAW_HDFS (2,075,259 rows)"
  info "Output : $out"
  local start; start=$(date +%s)
  hadoop jar "$jar" \
    -D mapreduce.job.name="$name" \
    -D mapreduce.job.reduces=1 \
    -files "$job/$mapper,$job/$reducer" \
    -mapper "$py $mapper" -reducer "$py $reducer" \
    -input "$RAW_HDFS" -output "$out" 2>&1 \
    | grep --line-buffered -E "Running job|map [0-9]+% reduce|completed successfully|Map input records|Map output records|Reduce output records|Launched map tasks|Launched reduce tasks|ERROR|FAILED"
  hdfs dfs -test -e "$out/_SUCCESS" 2>/dev/null || die "The job failed. See the YARN page http://127.0.0.1:8088"
  hdfs dfs -cat "$out/part-*" 2>/dev/null > "$local_copy"
  ok "$name finished in $(( $(date +%s) - start )) s; $(wc -l < "$local_copy" | tr -d ' ') result lines saved to $local_copy"
}
