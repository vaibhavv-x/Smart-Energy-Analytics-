#!/bin/bash
# STEP 9: start the live R Shiny dashboard on port 3838 and open it in the browser.
# It reads the saved results, so Hadoop does not have to be running.
# This window stays busy while the dashboard runs. Press Ctrl+C here to stop it.
source "$(dirname "$0")/env.sh"
title "Step 9: R Shiny dashboard"
[ -s r/output/model_metrics.csv ] || die "No results yet. Run steps 1 to 7 first."
info "Dashboard at http://127.0.0.1:3838  (press Ctrl+C in this window to stop it)"
info "Use a second Terminal window for step 10 and step 11."
Rscript -e 'shiny::runApp("r/dashboard", port = 3838, host = "127.0.0.1", launch.browser = TRUE)'
