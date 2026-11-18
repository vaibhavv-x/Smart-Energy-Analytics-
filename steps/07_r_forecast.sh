#!/bin/bash
# STEP 7: R predicts tomorrow's electricity use (r/forecast_models.R).
# Reads the feature table Hive built, splits the days by time (train / validation / test),
# and compares a naive baseline, linear regression (lm) and a random forest (randomForest).
# Does not need Hadoop. Results go to r/output/.
source "$(dirname "$0")/env.sh"
title "Step 7: forecasting in R"
[ -s hive/cluster_results/daily_features.csv ] || die "No feature table yet. Run steps 5 and 6 first."
Rscript r/forecast_models.R || die "The R forecast failed."
ok "Next:  bash steps/08_r_graphs.sh"
