#!/bin/bash
# STEP 10: run the 18 automated checks (tests/). They confirm that MapReduce and Hive give the same
# numbers, that Hive counted every raw row, that the features use only past days, and that the
# R models beat the naive baseline.
source "$(dirname "$0")/env.sh"
title "Step 10: automated checks"
VENV="$BD/venv"
[ -x "$VENV/bin/python" ] || python3 -m venv "$VENV"
"$VENV/bin/python" -c "import pytest" 2>/dev/null || "$VENV/bin/python" -m pip install --quiet pytest
"$VENV/bin/python" -m pytest tests -v -p no:cacheprovider || die "Some checks failed."
ok "All checks passed. When you are finished:  bash steps/11_stop_everything.sh"
