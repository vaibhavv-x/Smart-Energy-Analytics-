# Technical Limitations & System Boundaries

## Smart Energy Consumption Analytics & Forecasting
**Batch**: 30  
**Team**: Vaibhav (AP23110010425) & Saubhagya Kashyap (AP23110010439)

---

## 1. Dataset Limitations

1. **Single Household Representation**:
   - The UCI dataset represents a single residential household located in Sceaux (near Paris, France). Consequently, absolute demand levels and lifestyle patterns cannot be generalized directly to commercial buildings, microgrids, or households in different climatic zones without transfer learning.
2. **Absence of Exogenous Weather Telemetry**:
   - Household electricity consumption—specifically heating (Sub 3) in winter and air conditioning in summer—is strongly driven by ambient temperature, relative humidity, and solar irradiance. The dataset lacks weather telemetry, restricting features to internal historical lags and calendar indicators.
3. **Sub-Metering Coarseness**:
   - Only three electrical sub-meters are available (Kitchen, Laundry, Climate/Water). Over 58% of active energy resides in the unmetered remainder (lighting, small appliances, entertainment). Non-Intrusive Load Monitoring (NILM) for individual appliance disaggregation is not feasible without high-frequency transient sampling ($> 1 \text{ kHz}$).
4. **Sensor Downtime & Missing Intervals**:
   - Approximately 1.25% of readings (25,979 minutes) were recorded as missing (`?`), including an extended outage during August 2008. In accordance with strict academic standards, these periods were not artificially interpolated.

---

## 2. Infrastructure & Environment Limitations

1. **Host Hardware Constraints (8 GB RAM)**:
   - The development MacBook (Apple M1) has 8 GB of physical RAM. Running concurrent distributed daemons (Hadoop NameNode, DataNode, YARN ResourceManager, NodeManager, Hive Metastore, and Spark Worker) simultaneously exceeds available RAM, risking Out-Of-Memory (OOM) operating system thrashing.
   - *Mitigation*: The project adopted a resource-conscious sequential execution architecture and single-worker local Spark mode (`local[1]`).
2. **Single-Node Cluster**:
   - HDFS, YARN and HiveServer2 all run on one MacBook with replication factor 1. The dataset (126.8 MB) fits in a single HDFS block, so jobs use one or two map tasks. The pipeline shows the workflow of a cluster, not its scale or fault tolerance.
3. **Spark Runs in Local Mode**:
   - Spark reads its inputs from HDFS and writes the feature table back to HDFS, but the computation runs in a local Spark session (`local[1]`), not on YARN.
4. **Hive Uses the MapReduce Engine and an Embedded Metastore**:
   - Hive 4.0.1 runs queries as MapReduce jobs on YARN (Tez is not installed), so each aggregation takes 20 to 90 seconds on tables of a few thousand rows. The metastore is an embedded Derby database, which allows only one HiveServer2 process.
5. **Java Versions**:
   - Hadoop 3.3.6, Hive 4.0.1 and PySpark 3.5.3 run on Java 11. The Mac's default Java 25 is not supported by them, so `run_on_mac.sh` installs its own JDK 11.

---

## 3. Machine Learning Forecasting Boundaries

1. **Stochastic Behavioral Variability**:
   - Day-to-day residential electricity demand exhibits high intrinsic variance ($R^2 \approx 0.48$). Unpredictable human behaviors—such as spontaneous social gatherings, late-night baking, or sudden travel—cannot be inferred solely from past electrical consumption lags.
2. **Single-Step vs. Multi-Step Forecasting**:
   - The primary forecasting target is single-step next-day prediction ($t+1$). Multi-step recursive forecasting ($t+7, t+30$) experiences compounding error propagation when predicted values are fed back recursively into lag features.
