# Run the project step by step

One script per stage, numbered in the order you run them. Each script explains itself when it runs, and the comment at the top of each file says what it does.

## How to use

Open **Terminal** and go to the project folder:

```bash
cd "/Users/tanishchhabra/big data/Smart-Energy-Analytics-Forecasting"
```

Then run the steps one at a time:

| Step | Command | What it does | Time |
|---|---|---|---|
| 0 | `bash steps/00_check_setup.sh` | Checks Java, Hadoop, Hive, R and the dataset are installed | seconds |
| 1 | `bash steps/01_start_cluster.sh` | Starts HDFS, YARN and Hive | 1–5 min |
| 2 | `bash steps/02_load_data_into_hdfs.sh` | Uploads the dataset into HDFS, from scratch | 30 s |
| 3 | `bash steps/03_mapreduce_daily_totals.sh` | MapReduce job 1: energy per day | 30 s |
| 4 | `bash steps/04_mapreduce_hourly_profile.sh` | MapReduce job 2: power per hour of the day | 30 s |
| 5 | `bash steps/05_hive_build_tables.sh` | Hive cleans the raw data into tables and builds the forecasting features | 2–3 min |
| 6 | `bash steps/06_hive_run_queries.sh` | Runs the 12 Hive queries and prints their results | 8–10 min |
| 7 | `bash steps/07_r_forecast.sh` | R predicts tomorrow's electricity use | 10 s |
| 8 | `bash steps/08_r_graphs.sh` | R draws the 12 graphs and opens the folder | 10 s |
| 9 | `bash steps/09_dashboard.sh` | Live R Shiny dashboard at http://127.0.0.1:3838 | stays running |
| 10 | `bash steps/10_tests.sh` | 18 automated checks | seconds |
| 11 | `bash steps/11_stop_everything.sh` | Switches everything off | 10 s |

Or run steps 0 to 8 and 10 in one go (about 20 minutes): `bash steps/run_all.sh`

## Things to know

- **Order matters for steps 1 to 6.** Each one uses what the previous one made. Steps 7 to 10 only read saved files, so they also work with Hadoop switched off.
- **Step 9 keeps its Terminal window busy.** Open a second Terminal window (Cmd + N) for steps 10 and 11. Press **Ctrl + C** in the step 9 window to stop the dashboard.
- **Close other apps first.** Hadoop and Hive need most of the 8 GB of RAM.
- **Always finish with step 11**, so nothing keeps running in the background.

## Where to look while it runs

| Address | What you see | After step |
|---|---|---|
| http://127.0.0.1:9870 | HDFS: Utilities → Browse the file system → `/smart-energy` | 1 |
| http://127.0.0.1:8088 | YARN: every MapReduce job and Hive query, with its status | 1 |
| http://127.0.0.1:10002 | Hive server: sessions and queries | 1 |
| http://127.0.0.1:3838 | Our R Shiny dashboard | 9 |

## If something goes wrong

| Message | Fix |
|---|---|
| `Hadoop is not running` or `Hive is not running` | Run step 1. Hive starts last; wait a minute after step 1 finishes. |
| `Name node is in safe mode` | HDFS is still starting. Wait 30 seconds and run the step again. |
| `[MISSING]` in step 0 | Run `bash run_on_mac.sh` once; it installs everything. |
| A step stops with `[STOP]` | Read the message. If unsure, run step 11, then step 1, then repeat the step. |

## Files the steps use

| Step | Files |
|---|---|
| 3 | `hadoop/mapper.py`, `hadoop/reducer.py` |
| 4 | `hadoop/mapper_hourly.py`, `hadoop/reducer_hourly.py` |
| 5 | `hive/schema.hql`, `hive/build_tables.hql`, `hive/features.hql` |
| 6 | `hive/queries.hql` |
| 7 | `r/forecast_models.R` |
| 8 | `r/visualize.R` |
| 9 | `r/dashboard/app.R` |
| 10 | `tests/` |
