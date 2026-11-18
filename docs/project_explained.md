# The project explained simply

## The idea in one paragraph

A smart meter recorded the electricity used by one house every minute for four years: 2,075,259 rows. We store that file in Hadoop, use MapReduce and Hive to turn the minutes into days, hours and answers to questions, and use R to predict tomorrow's use and to draw charts and a dashboard.

```
dataset file → HDFS (storage) → MapReduce + Hive (processing) → R (prediction, graphs, dashboard)
```

---

## What each tool does

### HDFS (Hadoop Distributed File System): the storage

**What it is:** a file system built for huge files. It cuts a file into blocks of 128 MB and spreads them over many computers, keeping copies so nothing is lost if a computer fails.

**In our project:** it stores the dataset (`/smart-energy/raw`), the outputs of the MapReduce jobs (`/smart-energy/mapreduce`) and the Hive tables (`/smart-energy/hive/warehouse`). Our file is 126.8 MB, so it fits in one block.

**Its two programs:**
- **NameNode:** the index. It knows which blocks make up each file and where they are.
- **DataNode:** the storage. It holds the blocks themselves.

**Where you see it:** http://127.0.0.1:9870

### YARN: the manager

**What it is:** the part of Hadoop that hands out memory and CPU to jobs and runs them.

**In our project:** every MapReduce job and every Hive query runs through YARN.

**Its two programs:**
- **ResourceManager:** receives jobs and decides where they run.
- **NodeManager:** starts the tasks on the machine.

**Where you see it:** http://127.0.0.1:8088 lists every job with its status (SUCCEEDED or FAILED).

### MapReduce: the counting machine

**What it is:** a way to process a huge file in parallel, in two steps.

1. **Map:** read each line and turn it into a pair: a **key** (a label to group by) and a **value** (a number).
2. **Shuffle and sort** (done by Hadoop automatically): bring together all pairs with the same key.
3. **Reduce:** for each key, combine its values (here: add them up).

Because each line can be mapped independently, many computers can work on different parts of the file at the same time.

**Yes, we use MapReduce, in two places:**

1. **Our two MapReduce jobs**, written in Python and run with Hadoop Streaming:

| Job | Map step (key, value) | Reduce step | Result | Why |
|---|---|---|---|---|
| **Job 1: daily totals** (`mapper.py`, `reducer.py`) | key = date, value = energy of that minute (kW ÷ 60 = kWh) | add up the energy and count the readings for each date | 1,433 lines: date, kWh, readings | How much electricity the house used each day |
| **Job 2: hourly profile** (`mapper_hourly.py`, `reducer_hourly.py`) | key = hour of the day (00 to 23), value = energy and power | total energy, number of readings, average power and highest power for each hour | 24 lines | At what time of day the house uses the most power |

Example for job 1, with three minutes of data:

```
raw lines                          map output              reduce output
16/12/2006;17:24:00;4.216;...  →   16/12/2006  0.0703  1
16/12/2006;17:25:00;5.360;...  →   16/12/2006  0.0893  1   →   16/12/2006  0.1596  2
17/12/2006;00:00:00;1.044;...  →   17/12/2006  0.0174  1   →   17/12/2006  0.0174  1
```

2. **Inside Hive:** every Hive query is turned into MapReduce jobs automatically (see below).

### Hive: SQL on Hadoop

**What it is:** a data warehouse on top of Hadoop. You write SQL (called HiveQL); Hive turns it into MapReduce jobs, runs them on YARN, and returns the result as a table. The data stays as files in HDFS.

**In our project, Hive does three jobs:**

| Job | File | What it does |
|---|---|---|
| **Create tables** | `hive/schema.hql` | Creates the database `smart_energy_db` and three tables: `raw_household_power` (points at the raw file in HDFS), `daily_energy_consumption` (ORC format, one folder per year) and `hourly_energy_consumption` (Parquet format) |
| **Preprocessing** | `hive/build_tables.hql` | Cleans the raw data: removes missing readings (`?`), converts kW to kWh, adds up each day and each hour, and marks a day as valid when at least 85% of its readings exist |
| **Features for forecasting** | `hive/features.hql` | Builds the inputs for the prediction model: yesterday's use, use 2 and 7 days ago, the average of the last 7 and 14 days, and so on |
| **12 analysis queries** | `hive/queries.hql` | Answers the project's questions (listed below) |

**Its parts:**
- **HiveServer2:** the server that receives queries (port 10000; web page at http://127.0.0.1:10002).
- **Beeline:** the command-line client you type SQL into.
- **Metastore:** where Hive remembers which tables exist and their columns (a small Derby database).

**Formats:** ORC and Parquet are column-based file formats. They compress well and let a query read only the columns it needs.

### R: prediction, graphs and the dashboard

**What it is:** a programming language for statistics and charts.

**In our project:**

| File | What it does |
|---|---|
| `r/forecast_models.R` | Predicts tomorrow's electricity use from the features Hive built. Compares three methods: a naive guess (tomorrow = today), linear regression (`lm`) and a random forest (`randomForest`). The random forest wins: average error 3.79 kWh against 4.50 for the naive guess. |
| `r/visualize.R` | Draws the 12 graphs for the report into `graphs/`. |
| `r/dashboard/app.R` | The live dashboard (R Shiny), served at http://127.0.0.1:3838. |

### Supporting tools

| Tool | Why it is there |
|---|---|
| **Java 11** | Hadoop and Hive are written in Java and need it to run |
| **Python 3** | Only for the MapReduce mapper and reducer scripts, the Hive runner script and the tests. No Spark, no PySpark. |
| **Bash scripts** (`steps/`, `run_on_mac.sh`) | Start, run and stop everything with simple commands |
| **pytest** | 18 automated checks that the results are correct |

---

## What each Hive query does

All 12 are in `hive/queries.hql`; their results are in `hive/cluster_results/q01.csv` to `q12.csv`.

| Query | Question it answers | How (in plain words) | Result |
|---|---|---|---|
| **Q1** Daily consumption | How much electricity was used each day? | List every valid day with its total kWh | 1,420 days, from about 4 to 80 kWh a day |
| **Q2** Monthly totals | How much was used each month of each year? | Group the days by year and month; total and average | 48 months |
| **Q3** Hourly profile | How much is used in each hour of the day, on average? | Group the hourly table by hour (0 to 23); average | 24 hours; lowest at 04:00, highest at 20:00 |
| **Q4** Peak hours | Which five hours are the busiest? | Same as Q3, sorted from highest, top 5 | 20:00, 21:00, 19:00, 07:00, 08:00 |
| **Q5** Top days | Which ten days used the most? | Sort the days by energy, top 10 | Highest: 23 Dec 2006, 79.56 kWh |
| **Q6** Weekday vs weekend | Do weekends use more? | Group the days into weekday and weekend; average | Weekend 29.59, weekday 24.84 kWh a day (19.1% more) |
| **Q7** Seasons | Which months use the most, over all years? | Group by calendar month; average | December 35.6 kWh a day, August 13.7 |
| **Q8** Sub-meters | What uses the energy? | Add up each sub-meter and divide by the total | Water heater and air conditioner 35.5%, laundry 7.1%, kitchen 6.2%, not sub-metered 51.2% |
| **Q9** Year-on-year | Did each month use more or less than the same month a year earlier? | Join each month to the same month of the previous year; % change | 36 month pairs |
| **Q10** Heavy days | How often does the house use more than 40 kWh in a day? | Count days above 40 kWh, per year | Fell from 12.2% of days in 2007 to 4.1% in 2010 |
| **Q11** Time of day | Which part of the day uses the most? | Put each hour into night, morning, afternoon or evening; share of total | Evening 35.0%, morning 28.9%, afternoon 24.5%, night 11.5% |
| **Q12** Data quality | How many readings are missing? | Count readings and missing readings per year, on the raw table (all 2,075,259 rows) | 25,979 missing (1.25%); worst year 2010 (3.7%) |

**Besides these 12**, Hive runs SQL in two other files: `build_tables.hql` (2 queries that build the daily and hourly tables from the raw data) and `features.hql` (1 query with window functions that builds the forecasting features).

---

## Where you do what

| Place | What you do there |
|---|---|
| **Terminal** | Run the step scripts and type commands |
| **Beeline** (inside Terminal) | Type Hive SQL by hand: `beeline -u jdbc:hive2://localhost:10000/smart_energy_db -n $USER` |
| **Browser, http://127.0.0.1:9870** | See the files in HDFS |
| **Browser, http://127.0.0.1:8088** | See the MapReduce jobs and Hive queries running |
| **Browser, http://127.0.0.1:10002** | See the Hive server |
| **Browser, http://127.0.0.1:3838** | Our dashboard |
| **Finder, `graphs/`** | The 12 report graphs |
| **VS Code** | Read the code: `hadoop/`, `hive/`, `r/` |

---

## What we did not use

Spark, PySpark, Pig, HBase, Sqoop, Kafka, Power BI, Tableau.
