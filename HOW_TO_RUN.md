# How to run the project, step by step

> **Easiest way:** run the numbered scripts in the [steps/](steps/) folder, one per stage (see [steps/README.md](steps/README.md)). This page shows the same stages with the commands typed by hand, which is useful for showing each tool live.

This guide is for running and showing the project on the MacBook where it is already installed. Everything is typed in the **Terminal** app; results are seen in the **browser** (Chrome or Safari) and in **Finder**.

Total time for the full demo: about 15 minutes.

---

## Before you start

- Close heavy apps (Chrome with many tabs, games). Hadoop and Hive need most of the 8 GB of RAM.
- Open **Terminal** (press Cmd + Space, type `Terminal`, press Enter).
- Keep this file open next to it.

Every command block below is copied into Terminal as a whole and run with Enter.

---

## Step 1. Go to the project folder

```bash
cd "/Users/tanishchhabra/big data/Smart-Energy-Analytics-Forecasting"
```

The quotes are needed because the folder name `big data` has a space in it.

---

## Step 2. Start the cluster (HDFS, YARN, Hive)

```bash
bash run_on_mac.sh start
```

**What happens:** four Hadoop programs start (NameNode, DataNode, ResourceManager, NodeManager), then the Hive server starts.

**How long:** 1 to 5 minutes. The first start after the Mac has been restarted is the slowest. Wait until you see:

```
HDFS UI       http://localhost:9870
YARN UI       http://localhost:8088
HiveServer2   http://localhost:10002
```

**Check it worked:**

```bash
bash run_on_mac.sh status
```

You should see `NameNode`, `DataNode`, `ResourceManager`, `NodeManager` and `RunJar` (RunJar is Hive), followed by a list of the files in HDFS.

---

## Step 3. Make the Hadoop commands available in this Terminal window

```bash
export JAVA_HOME=$(ls -d ~/bigdata/jdk-11*/Contents/Home)
export HADOOP_HOME=~/bigdata/hadoop-3.3.6
export HIVE_HOME=~/bigdata/apache-hive-4.0.1-bin
export PATH=$JAVA_HOME/bin:$HADOOP_HOME/bin:$HIVE_HOME/bin:$PATH
```

Nothing is printed. This only lasts for this Terminal window; if you open a new window, run it again.

---

## Step 4. HDFS: see the data stored in Hadoop

**In Terminal:**

```bash
hdfs dfs -ls /smart-energy
hdfs dfs -ls -h /smart-energy/raw
hdfs dfs -cat /smart-energy/raw/household_power_consumption.txt | head -5
```

The first line lists the project folders; the second shows the 126.8 MB dataset; the third prints its first five rows.

**In the browser:** open http://localhost:9870, click **Utilities → Browse the file system**, type `/smart-energy` and press **Go**. Click into `raw`, `mapreduce` and `hive/warehouse/smart_energy_db.db/daily_energy_consumption` (one folder per year).

---

## Step 5. MapReduce: run a job live

This runs MapReduce job 2 (the hour-of-day load profile) over all 2,075,259 rows. It writes to a new folder, `demo_hourly`, so the saved results are not touched.

```bash
mkdir -p ~/bigdata/job
cp hadoop/mapper_hourly.py hadoop/reducer_hourly.py ~/bigdata/job/
hdfs dfs -rm -r -f /smart-energy/mapreduce/demo_hourly

hadoop jar $HADOOP_HOME/share/hadoop/tools/lib/hadoop-streaming-3.3.6.jar \
  -D mapreduce.job.name="demo-hourly-profile" \
  -files $HOME/bigdata/job/mapper_hourly.py,$HOME/bigdata/job/reducer_hourly.py \
  -mapper "python3 mapper_hourly.py" -reducer "python3 reducer_hourly.py" \
  -input /smart-energy/raw/household_power_consumption.txt \
  -output /smart-energy/mapreduce/demo_hourly
```

**How long:** about 20 seconds. Watch for `map 100% reduce 100%` and `completed successfully`.

**See the result:**

```bash
hdfs dfs -cat /smart-energy/mapreduce/demo_hourly/part-00000
```

24 lines, one per hour: hour, total kWh, number of readings, average kW, peak kW. Hour `20` has the highest average (about 1.90 kW), hour `04` the lowest (about 0.44 kW).

**In the browser:** open http://localhost:8088. The job `demo-hourly-profile` is at the top with State `FINISHED` and FinalStatus `SUCCEEDED`.

---

## Step 6. Hive: run SQL queries live

**Open the Hive prompt:**

```bash
beeline -u jdbc:hive2://localhost:10000/smart_energy_db -n $USER
```

You get a prompt like `0: jdbc:hive2://localhost:10000/smart_energy_db>`. Type these one at a time (each ends with `;`):

```sql
SHOW TABLES;

DESCRIBE daily_energy_consumption;

SHOW PARTITIONS daily_energy_consumption;

SELECT year_num, COUNT(*) AS days, ROUND(AVG(total_energy_kwh), 2) AS avg_kwh_per_day
FROM daily_energy_consumption
WHERE is_valid_day = 1
GROUP BY year_num
ORDER BY year_num;

SELECT CASE WHEN is_weekend = 1 THEN 'Weekend' ELSE 'Weekday' END AS day_type,
       ROUND(AVG(total_energy_kwh), 2) AS avg_kwh_per_day
FROM daily_energy_consumption
WHERE is_valid_day = 1
GROUP BY is_weekend;
```

The two `SELECT` queries each take 20 to 45 seconds, because Hive turns them into MapReduce jobs on YARN (you can watch them appear at http://localhost:8088). Weekend should show about 29.59 and Weekday about 24.84.

To leave the Hive prompt, type `!quit` and press Enter.

All 12 project queries are in `hive/queries.hql`, and their saved results are in `hive/cluster_results/q01.csv` to `q12.csv`.

---

## Step 7. R: forecasting and graphs

```bash
Rscript r/forecast_models.R
Rscript r/visualize.R
open graphs
```

The first command prints a table comparing the three models; the random forest should be selected with a test MAE of about 3.79 kWh, against 4.50 for the naive baseline. The second redraws the 12 graphs. The third opens the `graphs` folder in Finder; double-click any picture to see it.

R does not need Hadoop to be running: it reads the result files that MapReduce and Hive saved.

---

## Step 7b. Open the live dashboard (R Shiny)

```bash
bash run_on_mac.sh dashboard
```

**What happens:** R starts a small web server on port 3838 and opens http://127.0.0.1:3838 in your browser. If the browser does not open, paste that address into it.

The dashboard has seven pages: Overview, Time of day, Seasons and weekends, What uses the energy, Forecast, Hive queries (the SQL of all 12 queries and their results) and About. You can drag the date slider, tick years and models, and pick a Hive query.

It reads the results that MapReduce, Hive and R saved, so it works even when Hadoop is stopped. The Terminal window stays busy while the dashboard runs; press **Ctrl + C** in it to stop the dashboard.

---

## Step 8. Run the automated checks (in a new Terminal window if the dashboard is running)

```bash
bash run_on_mac.sh test
```

It should end with `18 passed` and `All tests passed`.

---

## Step 9. Stop everything when you finish

```bash
hdfs dfs -rm -r -f /smart-energy/mapreduce/demo_hourly
bash run_on_mac.sh stop
```

This removes the demo job's output and stops Hive and Hadoop, which frees the memory. The data stays in HDFS for next time.

---

## Running the whole pipeline from the beginning (optional)

```bash
bash run_on_mac.sh
```

This re-runs everything: both MapReduce jobs, all the Hive steps (building the tables from the raw data, the features and the 12 queries), R and the tests. It takes about 15 minutes, of which Hive is about 12. You do not need to do this for a demo; the steps above show every tool working.

---

## If something goes wrong

| Problem | Fix |
|---|---|
| `command not found: hdfs` (or `hadoop`, `beeline`) | Run Step 3 again in this Terminal window. |
| `Connection refused` from `hdfs` or `beeline` | The cluster is not running. Run Step 2 and wait for the three web addresses. |
| `beeline` says it cannot connect, right after Step 2 | Hive takes a little longer than Hadoop to start. Wait one minute and try again. |
| MapReduce says the output directory already exists | Run `hdfs dfs -rm -r -f /smart-energy/mapreduce/demo_hourly`, then the job again. |
| `Name node is in safe mode` | HDFS is still starting. Wait 30 seconds and try again. |
| The Mac becomes very slow | Close other apps. If it does not recover, run `bash run_on_mac.sh stop` and start again. |
| Anything else | Run `bash run_on_mac.sh stop`, then `bash run_on_mac.sh start`, and repeat the step. |

---

## The web pages

| Address | What it is | What to show |
|---|---|---|
| http://localhost:9870 | HDFS (Hadoop's file system) | Utilities → Browse the file system → `/smart-energy` |
| http://localhost:8088 | YARN (Hadoop's job manager) | The list of MapReduce and Hive jobs, all SUCCEEDED |
| http://localhost:10002 | Hive server | Sessions and the queries that ran |
| http://127.0.0.1:3838 | Our R Shiny dashboard | All the results, with filters (runs while Step 7b is running) |

They only work while the cluster is running (after Step 2, before Step 9).
