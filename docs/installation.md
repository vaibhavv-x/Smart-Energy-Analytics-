# Installation Guide (macOS)

## Smart Energy Consumption Analytics & Forecasting
**Batch**: 30  
**Team**: Vaibhav (AP23110010425) & Saubhagya Kashyap (AP23110010439)

---

## 1. What you need

- A Mac (Apple Silicon or Intel) with macOS 12 or later, 8 GB of RAM and about 5 GB of free disk space.
- `python3` version 3.9 or newer. Check with `python3 --version`; if it is missing, run `xcode-select --install`.
- An internet connection for the first run (about 1.3 GB of downloads).

You do not need sudo, Homebrew or Docker. Nothing is installed system-wide.

## 2. One-command setup

From the project folder:

```bash
bash run_on_mac.sh
```

The script installs and runs everything in ten stages. A finished stage is skipped on the next run, so it is safe to run again after an error or a dropped download.

| Stage | What it does | Where it goes |
|---|---|---|
| 1. Java 11 | Downloads Temurin JDK 11 (about 190 MB) | `~/bigdata/jdk-11*` |
| 2. Hadoop | Downloads Hadoop 3.3.6 (about 700 MB) and writes the single-node configuration | `~/bigdata/hadoop-3.3.6` |
| 3. Dataset | Downloads the UCI file (20 MB zipped, 126.8 MB unpacked) | `data/raw/household_power_consumption.txt` |
| 4. Python | Creates a virtual environment with the packages in `requirements.txt` and PySpark 3.5.3 | `~/bigdata/venv` |
| 5. Cluster | Formats HDFS on the first run; starts NameNode, DataNode, ResourceManager, NodeManager | `~/bigdata/hadoop_data` |
| 6. HDFS | Creates `/smart-energy` and uploads the dataset | HDFS |
| 7. MapReduce | Runs two Hadoop Streaming jobs on YARN | `hadoop/mapreduce_yarn_*.txt` |
| 8. Pipeline | Cleaning, upload of cleaned tables to HDFS, Spark SQL, PySpark features, MLlib, exports, tests | `data/`, `hive/query_results/`, `forecasting/`, `screenshots/` |
| 9. Check | Compares the MapReduce daily totals with the pipeline's daily table | terminal |
| 10. Hive | Downloads Hive 4.0.1 (about 390 MB), starts HiveServer2, loads the tables, runs 12 queries | `~/bigdata/apache-hive-4.0.1-bin`, `hive/cluster_results/` |

The first run takes 20 to 40 minutes, mostly downloads. Later runs take about 12 minutes, of which Hive is about 9.

## 3. Other commands

```bash
bash run_on_mac.sh status     # running daemons and HDFS contents
bash run_on_mac.sh hive       # run only the Hive stage again
bash run_on_mac.sh dashboard  # open the Streamlit dashboard at http://localhost:8501
bash run_on_mac.sh stop       # stop HiveServer2 and Hadoop
```

Web pages while the cluster is running:

| Page | Address |
|---|---|
| HDFS NameNode | http://localhost:9870 |
| YARN ResourceManager | http://localhost:8088 |
| HiveServer2 | http://localhost:10002 |
| Dashboard | http://localhost:8501 |

## 4. Running one script by hand

The Spark scripts need Java 11 and the project's Python environment:

```bash
export JAVA_HOME=$(ls -d ~/bigdata/jdk-11*/Contents/Home)
export SMART_ENERGY_HDFS_URI=hdfs://localhost:9000/smart-energy   # leave unset to read local CSV files
~/bigdata/venv/bin/python hive/run_hive_analytics.py
```

To use `hdfs`, `yarn` or `beeline` directly:

```bash
export JAVA_HOME=$(ls -d ~/bigdata/jdk-11*/Contents/Home)
export HADOOP_HOME=~/bigdata/hadoop-3.3.6
export HIVE_HOME=~/bigdata/apache-hive-4.0.1-bin
export PATH=$JAVA_HOME/bin:$HADOOP_HOME/bin:$HIVE_HOME/bin:$PATH

hdfs dfs -ls -R /smart-energy
beeline -u jdbc:hive2://localhost:10000/smart_energy_db -n $USER
```

## 5. Troubleshooting

| Symptom | Cause and fix |
|---|---|
| A download stops or the script says "download failed" | Run `bash run_on_mac.sh` again; downloads resume where they stopped. |
| `[STOP] ... did not start` for a Hadoop daemon | The script prints the daemon's log. Usually a port is in use by an old daemon: run `bash run_on_mac.sh stop`, then start again. |
| Spark fails with an unsupported Java version | The Mac's default Java is newer than Spark supports. Set `JAVA_HOME` as in section 4. |
| Hive INSERT fails with `NoSuchMethodError ... protobuf` | `mapreduce.job.user.classpath.first` must be `true` in `hive-site.xml`. The script writes this; re-run `bash run_on_mac.sh hive`. |
| The Mac becomes slow | Hadoop, HiveServer2 and Spark together use most of 8 GB. Close other apps, and run `bash run_on_mac.sh stop` when finished. |
| `python scripts/run_pipeline.py` produced three days of data | The full dataset was missing, so the sample was used. Restore with `git checkout -- data forecasting hive dashboard screenshots` and run `bash run_on_mac.sh`. |

## 6. Removing everything

```bash
bash run_on_mac.sh stop
rm -rf ~/bigdata
```

This deletes Java 11, Hadoop, Hive, the Python environment and all HDFS data. The project folder is not touched.

## 7. Other platforms

The pipeline itself (`scripts/run_pipeline.py`) runs on Linux and Windows with Python 3.9 or newer, Java 11 or 17 and `pip install -r requirements.txt`. The cluster setup in `run_on_mac.sh` is written for macOS; on Linux the same steps work with a Linux JDK.
