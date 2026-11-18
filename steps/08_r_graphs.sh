#!/bin/bash
# STEP 8: R draws the 12 report graphs (r/visualize.R) from the MapReduce, Hive and forecast results,
# saves them as PNG files in graphs/, and opens the folder.
source "$(dirname "$0")/env.sh"
title "Step 8: graphs in R"
Rscript r/visualize.R || die "Drawing the graphs failed."
open graphs
ok "Graphs saved in graphs/ (the folder is now open). Next:  bash steps/09_dashboard.sh"
