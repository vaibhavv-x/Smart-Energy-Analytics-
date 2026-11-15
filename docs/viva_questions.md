# Viva Questions and Answers

**Smart Energy Analytics, Batch 30** — Vaibhav (AP23110010425) and Saubhagya Kashyap (AP23110010439)

## Project

**1. What is the project in one sentence?**
We store four years of one-minute electricity readings from one household in HDFS, aggregate them with MapReduce, preprocess and query them in Hive, and forecast and plot the results in R.

**2. Which Hadoop ecosystem tools did you use, and for what?**
HDFS stores the raw file and the Hive tables. MapReduce on YARN runs two aggregation jobs. Hive does the preprocessing, twelve analysis queries and the feature engineering. R does the forecasting and all the graphs.

**3. Did you use Spark or PySpark?**
No. There is no Spark in the project. The MapReduce mappers and reducers are plain Python scripts run by Hadoop Streaming, which is MapReduce, not PySpark.

**4. What is the dataset?**
The UCI Individual Household Electric Power Consumption dataset: 2,075,259 one-minute readings from one home near Paris, December 2006 to November 2010, 126.8 MB. Each row has the date, time, active power, reactive power, voltage, current and three sub-meters.

**5. Is this big data?**
Not by volume: 126.8 MB fits in one HDFS block. We use it to demonstrate the full workflow on a real dataset. The same jobs and queries would run unchanged on a larger file and more nodes.

## HDFS and YARN

**6. How is the cluster set up?**
A single-node (pseudo-distributed) Hadoop 3.3.6 cluster: one NameNode and one DataNode for HDFS, one ResourceManager and one NodeManager for YARN, replication factor 1.

**7. What do the NameNode and DataNode do?**
The NameNode keeps the file system's metadata: the directory tree and which blocks make up each file. The DataNode stores the blocks themselves. A client asks the NameNode where a file's blocks are and reads them from the DataNodes.

**8. What is the block size, and how many blocks does your file use?**
128 MB by default. The file is 126.8 MB, so it uses one block.

**9. Why replication factor 1?**
There is only one DataNode, so there is nowhere to put a second copy. A real cluster uses 3.

**10. What does YARN do?**
It manages the cluster's resources. The ResourceManager accepts jobs and allocates containers; the NodeManager starts the containers on its machine. Each MapReduce job gets an ApplicationMaster container that requests containers for its map and reduce tasks.

## MapReduce

**11. Explain your two MapReduce jobs.**
Job 1: the mapper emits `date, kWh, 1` for every valid reading, and the reducer sums the energy and counts the readings for each date (1,433 days). Job 2: the mapper emits `hour, kWh, kW`, and the reducer returns the total energy, reading count, average power and peak power for each of the 24 hours.

**12. What happens between the mapper and the reducer?**
The shuffle and sort. Hadoop partitions the mapper's output by key, sorts it, and delivers all the values of one key to the same reducer, in key order. That is why the reducer can detect a new key by comparing it with the previous one.

**13. What is Hadoop Streaming?**
A utility that lets any program be a mapper or reducer. Hadoop writes input lines to the program's standard input and reads tab-separated key-value lines from its standard output.

**14. How many map and reduce tasks ran?**
Two map tasks and one reduce task for each job.

**15. How do you know the MapReduce results are correct?**
Hive computes the same daily energy from the same raw file with a completely different engine path. The two agree on all 1,420 valid days to within 0.001 kWh, with identical reading counts. A test checks this automatically.

## Hive

**16. What is Hive, and how does it run a query?**
A data warehouse on Hadoop. Tables are files in HDFS and their definitions are in the metastore. Hive parses a HiveQL query, plans it, and compiles it into jobs for its execution engine, here MapReduce on YARN.

**17. What is the difference between an external and a managed table?**
Dropping a managed table deletes its data; dropping an external table only removes the definition. Our raw table is external, because the file in `/smart-energy/raw` is the source data and must not be deleted. The daily and hourly tables are managed.

**18. Why is the daily table partitioned by year?**
Each year is stored in its own folder (`year_num=2007`, …). A query that filters on the year reads only that folder. We load it with dynamic partitioning, where Hive derives the partition from a column of the data.

**19. Why ORC and Parquet?**
Both are columnar formats: they store each column together, compress well, and let a query read only the columns it needs. We used ORC for the daily table and Parquet for the hourly table to show both.

**20. How is the preprocessing done?**
In HiveQL, in `hive/build_tables.hql`. Rows with a missing power reading are dropped; power is converted to energy (kW ÷ 60); sub-meters are converted from Wh to kWh; the rows are grouped by date, and by date and hour; and a day is marked valid when at least 85% of its readings are present.

**21. Why drop missing readings instead of filling them in?**
Filling in a missing minute would add energy that was never measured. Only 1.25% of readings are missing, and days with too many missing readings are excluded.

**22. Why does a Hive query take 20 seconds to 2 minutes on a small table?**
Every query starts one or more MapReduce jobs, and each job has to start an ApplicationMaster and task containers on YARN. That start-up cost dominates on small data. Tez would be faster.

**23. What problems did you face with Hive?**
Two. First, inserting into the ORC table failed with a protobuf `NoSuchMethodError`, because Hadoop ships protobuf 2.5 and Hive's ORC writer needs version 3; setting `mapreduce.job.user.classpath.first=true` fixed it. Second, the file's header line was being read as a data row, so the queries filter it out with `record_date <> 'Date'`.

**24. How are the forecasting features built?**
With window functions in `hive/features.hql`. `LAG` gives the consumption 1, 2 and 7 days earlier. `AVG(...) OVER (ORDER BY consumption_date ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING)` gives the mean of the previous seven days.

**25. What is data leakage, and how did you avoid it?**
Leakage is when a feature contains information from the day being predicted, which makes a model look better than it is. Every window ends at `1 PRECEDING`, so it never includes the current day, and a test recomputes the features from earlier days to confirm it.

## R

**26. What is R used for?**
Forecasting (`r/forecast_models.R`) and all twelve graphs (`r/visualize.R`). R reads the CSV results exported from Hive and the MapReduce output.

**27. Which models did you train?**
A naive baseline that predicts yesterday's consumption, linear regression (`lm`), and a random forest of 300 trees (`randomForest`).

**28. How did you split the data?**
By time, never shuffled: the first 989 days for training, the next 211 for validation, the last 213 for testing. Shuffling would let the model train on days after the ones it is tested on.

**29. What are the results?**
On the test period the random forest has a mean absolute error of 3.79 kWh and RMSE of 5.09 kWh, against 4.50 and 6.42 for the naive baseline. R² is 0.50.

**30. Why is R² only 0.50?**
One household's daily use depends on things the data does not contain, such as the weather and whether the family is at home. The model captures the level and the season but not single-day spikes.

**31. What do MAE, RMSE and R² mean?**
MAE is the average size of the error. RMSE squares the errors first, so large errors count more. R² is the share of the variation in the actual values that the model explains.

**32. Which features matter most?**
The mean of the previous seven days and the previous day's consumption, followed by the previous day's average power.

## Findings

**33. What are the main findings?**
Demand peaks at 20:00 (1.90 kW) and is lowest at 04:00 (0.44 kW). Weekends use 19.1% more than weekdays. December uses 2.6 times as much per day as August. The water heater and air conditioner take 35.5% of the energy, and 51.2% is not sub-metered. The evening carries 35% of the energy.

**34. What is the practical use?**
Moving water heating, laundry and dishwashing from the evening peak to the 01:00 to 05:00 valley would flatten the household's load curve, and a next-day forecast helps a utility plan supply.

**35. What are the limitations?**
Small data on a single node; one household in France; no weather data; Hive on the slow MapReduce engine; and a forecast that explains only half of the daily variation.

**36. What would you do next?**
Add temperature data, forecast each hour of the next day, use Tez for Hive, and repeat the analysis on a multi-household dataset that needs several blocks and nodes.
