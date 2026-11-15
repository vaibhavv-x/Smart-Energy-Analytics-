# ==============================================================================
# Data visualization in R
# Smart Energy Analytics (Batch 30)
#
# Reads the results produced on the Hadoop cluster (Hive query results and the
# MapReduce job output) and the forecasting results from r/forecast_models.R,
# and draws the report graphs into graphs/ as PNG files.
# Run from the project folder:  Rscript r/visualize.R
# ==============================================================================

hive_dir <- file.path("hive", "cluster_results")
out_dir <- "graphs"
dir.create(out_dir, showWarnings = FALSE)

# ---- shared style ---------------------------------------------------------------
surface <- "#fcfcfb"; ink <- "#0b0b0b"; ink2 <- "#52514e"; grid <- "#e4e3df"
blue <- "#2a78d6"; orange <- "#eb6834"; aqua <- "#1baf7a"; yellow <- "#eda100"
blue_light <- "#9ec5f4"; blue_dark <- "#184f95"

open_png <- function(name, width = 1600, height = 900) {
  png(file.path(out_dir, name), width = width, height = height, res = 160, bg = surface)
  par(mar = c(4.6, 4.8, 3.6, 1.6), bg = surface, fg = ink2, col.axis = ink2, col.lab = ink2,
      col.main = ink, family = "sans", cex.main = 1.05, font.main = 2, cex.lab = 0.9,
      cex.axis = 0.8, las = 1, bty = "n", mgp = c(3.1, 0.7, 0), tcl = -0.25)
}
hgrid <- function() abline(h = axTicks(2), col = grid, lwd = 1)
vgrid <- function() abline(v = axTicks(1), col = grid, lwd = 1)
subtitle <- function(text) mtext(text, side = 3, line = 0.35, adj = 0, cex = 0.72, col = ink2)
done <- function(name) { invisible(dev.off()); cat("  graphs/", name, "\n", sep = "") }

vbar <- function(values, labels, ylab, main, sub, fmt = "%.1f", col = blue, ymax = NULL) {
  if (is.null(ymax)) ymax <- max(values) * 1.15
  bp <- barplot(values, names.arg = labels, col = NA, border = NA, ylim = c(0, ymax), ylab = ylab, main = main)
  hgrid()
  barplot(values, col = col, border = surface, add = TRUE, axes = FALSE)
  if (!is.null(fmt)) text(bp, values, sprintf(fmt, values), pos = 3, cex = 0.72, col = ink)
  subtitle(sub)
  invisible(bp)
}

q <- function(n) read.csv(file.path(hive_dir, sprintf("q%02d.csv", n)), stringsAsFactors = FALSE)
names_clean <- function(d) { names(d) <- sub("^.*\\.", "", names(d)); d }

cat("Drawing graphs:\n")

# ---- 1. Daily consumption with 30-day average (Hive Q1) ---------------------------
d <- names_clean(q(1)); d$date <- as.Date(d$consumption_date)
ma30 <- stats::filter(d$daily_energy_kwh, rep(1 / 30, 30), sides = 1)
open_png("01_daily_consumption.png")
plot(d$date, d$daily_energy_kwh, type = "n", xlab = "", ylab = "Energy (kWh per day)",
     main = "Daily consumption swings between about 15 kWh in summer and 35 kWh in winter")
hgrid()
lines(d$date, d$daily_energy_kwh, col = blue_light, lwd = 1)
lines(d$date, ma30, col = blue_dark, lwd = 2.2)
legend("topright", c("Daily energy", "30-day average"), col = c(blue_light, blue_dark), lwd = c(1.5, 2.5),
       bty = "n", cex = 0.8, text.col = ink)
subtitle(sprintf("%s valid days, Dec 2006 to Nov 2010. Source: Hive query 1", format(nrow(d), big.mark = ",")))
done("01_daily_consumption.png")

# ---- 2. Hour-of-day load profile (MapReduce job 2) --------------------------------
h <- read.delim(file.path("hadoop", "mapreduce_yarn_hourly_output.txt"), header = FALSE,
                col.names = c("hour", "kwh", "readings", "avg_kw", "peak_kw"))
h <- h[order(h$hour), ]
open_png("02_hourly_load_profile.png")
vbar(h$avg_kw, sprintf("%02d", h$hour), "Average power (kW)",
     sprintf("Demand peaks at %02d:00 and is lowest at %02d:00", h$hour[which.max(h$avg_kw)], h$hour[which.min(h$avg_kw)]),
     sprintf("Average power in each hour of the day, from %s one-minute readings. Source: MapReduce job 2 on YARN",
             format(sum(h$readings), big.mark = ",")), fmt = NULL)
mtext("Hour of day", side = 1, line = 2.6, cex = 0.9, col = ink2)
done("02_hourly_load_profile.png")

# ---- 3. Seasonal pattern by calendar month (Hive Q7) ------------------------------
s <- names_clean(q(7)); s <- s[order(s$month_num), ]
open_png("03_monthly_seasonality.png")
vbar(s$seasonal_avg_daily_kwh, substr(s$month_name, 1, 3), "Average energy (kWh per day)",
     "Winter months use more than twice as much as August",
     "Average daily consumption by calendar month, all years. Source: Hive query 7")
done("03_monthly_seasonality.png")

# ---- 4. Monthly consumption by year (Hive Q2) -------------------------------------
m <- names_clean(q(2)); m <- m[m$year_num >= 2007, ]
years <- sort(unique(m$year_num)); cols <- c(blue, orange, aqua, yellow)[seq_along(years)]
open_png("04_monthly_by_year.png")
plot(NA, xlim = c(1, 12), ylim = c(0, max(m$avg_daily_kwh) * 1.1), xaxt = "n", xlab = "",
     ylab = "Average energy (kWh per day)", main = "The seasonal shape repeats every year")
axis(1, at = 1:12, labels = month.abb, tick = FALSE)
hgrid()
for (i in seq_along(years)) {
  y <- m[m$year_num == years[i], ]; y <- y[order(y$month_num), ]
  lines(y$month_num, y$avg_daily_kwh, col = cols[i], lwd = 2)
  points(y$month_num, y$avg_daily_kwh, col = cols[i], pch = 19, cex = 0.7)
}
legend("top", legend = years, col = cols, lwd = 2.5, pch = 19, horiz = TRUE, bty = "n", cex = 0.8, text.col = ink)
subtitle("Average daily consumption per month, 2007 to 2010 (2010 ends in November). Source: Hive query 2")
done("04_monthly_by_year.png")

# ---- 5. Weekday vs weekend (Hive Q6) ----------------------------------------------
w <- names_clean(q(6)); w <- w[order(w$day_category), ]
open_png("05_weekday_vs_weekend.png", width = 1200)
uplift <- (w$avg_daily_energy_kwh[w$day_category == "Weekend"] / w$avg_daily_energy_kwh[w$day_category == "Weekday"] - 1) * 100
vbar(w$avg_daily_energy_kwh, sprintf("%s\n(%d days)", w$day_category, w$total_days), "Average energy (kWh per day)",
     sprintf("Weekends use %.1f%% more than weekdays", uplift), "Source: Hive query 6", fmt = "%.2f")
done("05_weekday_vs_weekend.png")

# ---- 6. What uses the energy (Hive Q8) --------------------------------------------
u <- names_clean(q(8))
share <- c("Kitchen" = u$kitchen_percentage, "Laundry" = u$laundry_percentage,
           "Water heater and\nair conditioner" = u$climate_water_percentage, "Not sub-metered" = u$remainder_percentage)
share <- sort(share)
open_png("06_submetering_share.png")
par(mar = c(4.6, 9.5, 3.6, 2.5))
bp <- barplot(share, horiz = TRUE, col = NA, border = NA, xlim = c(0, max(share) * 1.15), xlab = "Share of total energy (%)",
              main = "About half of the energy is not covered by any sub-meter")
vgrid()
barplot(share, horiz = TRUE, col = blue, border = surface, add = TRUE, axes = FALSE, names.arg = rep("", length(share)))
text(share, bp, sprintf("%.1f%%", share), pos = 4, cex = 0.78, col = ink)
subtitle(sprintf("Share of %s kWh over 1,420 valid days. Source: Hive query 8", format(u$total_household_kwh, big.mark = ",")))
done("06_submetering_share.png")

# ---- 7. Time-of-day bands (Hive Q11) ----------------------------------------------
b <- names_clean(q(11)); b <- b[order(b$band), ]
open_png("07_time_of_day_bands.png", width = 1300)
vbar(b$share_pct, sub("^[0-9] ", "", sub(" \\(", "\n(", b$band)), "Share of total energy (%)",
     "The evening carries over a third of the household's energy", "Source: Hive query 11", fmt = "%.1f%%")
done("07_time_of_day_bands.png")

# ---- 8. High-consumption days per year (Hive Q10) ----------------------------------
g <- names_clean(q(10)); g <- g[g$year_num >= 2007, ]
open_png("08_high_consumption_days.png", width = 1300)
vbar(g$high_days_pct, g$year_num, "Days above 40 kWh (% of valid days)",
     "Heavy-consumption days became rarer every year",
     "2006 is left out because the data starts on 16 December. Source: Hive query 10", fmt = "%.1f%%")
done("08_high_consumption_days.png")

# ---- 9. Data quality per year (Hive Q12, raw table) --------------------------------
k <- names_clean(q(12))
open_png("09_missing_readings.png", width = 1300)
vbar(k$missing_pct, k$year_num, "Missing readings (%)",
     "Missing readings stay below 1% except in 2010",
     sprintf("%s of %s one-minute readings are missing. Source: Hive query 12 on the raw table",
             format(sum(k$missing_readings), big.mark = ","), format(sum(k$total_readings), big.mark = ",")), fmt = "%.2f%%")
done("09_missing_readings.png")

# ---- 10 to 12. Forecasting results (R models) --------------------------------------
pred_file <- file.path("r", "output", "test_predictions.csv")
if (file.exists(pred_file)) {
  p <- read.csv(pred_file, stringsAsFactors = FALSE); p$date <- as.Date(p$date)
  mt <- read.csv(file.path("r", "output", "model_metrics.csv"), stringsAsFactors = FALSE)
  imp <- read.csv(file.path("r", "output", "feature_importance.csv"), stringsAsFactors = FALSE)
  label <- c(Naive_Baseline = "Naive baseline", Linear_Regression = "Linear regression", Random_Forest = "Random forest")
  best <- mt$model[mt$selected == "yes"]
  best_col <- c(Linear_Regression = "linear_regression_kwh", Random_Forest = "random_forest_kwh", Naive_Baseline = "naive_baseline_kwh")[[best]]

  open_png("10_forecast_actual_vs_predicted.png")
  plot(p$date, p$actual_kwh, type = "n", xaxt = "n", xlab = "", ylab = "Energy (kWh per day)", ylim = c(0, max(p$actual_kwh) * 1.08),
       main = sprintf("The %s model follows the level of demand but misses sharp daily spikes", tolower(label[[best]])))
  ticks <- seq(as.Date("2010-05-01"), max(p$date), by = "month")
  axis(1, at = ticks, labels = format(ticks, "%b %Y"), tick = FALSE)
  hgrid()
  lines(p$date, p$actual_kwh, col = ink2, lwd = 1.4)
  lines(p$date, p[[best_col]], col = blue, lwd = 2.2)
  legend("top", c("Actual", paste(label[[best]], "prediction")), col = c(ink2, blue), lwd = c(1.6, 2.5),
         horiz = TRUE, bty = "n", cex = 0.8, text.col = ink)
  subtitle(sprintf("Held-out test period, %s to %s (%d days)", format(min(p$date), "%d %b %Y"), format(max(p$date), "%d %b %Y"), nrow(p)))
  done("10_forecast_actual_vs_predicted.png")

  open_png("11_model_comparison.png", width = 1400)
  vals <- rbind(mt$test_mae, mt$test_rmse)
  bp <- barplot(vals, beside = TRUE, names.arg = label[mt$model], col = NA, border = NA, ylim = c(0, max(vals) * 1.32),
                ylab = "Error on the test period (kWh per day)", main = "Both models beat the naive baseline")
  hgrid()
  barplot(vals, beside = TRUE, col = c(blue, orange), border = surface, add = TRUE, axes = FALSE)
  text(bp, vals, sprintf("%.2f", vals), pos = 3, cex = 0.72, col = ink)
  legend("topright", c("MAE (mean absolute error)", "RMSE (root mean squared error)"), fill = c(blue, orange), border = NA,
         bty = "n", cex = 0.78, text.col = ink)
  subtitle("Lower is better. The naive baseline predicts that tomorrow equals today")
  done("11_model_comparison.png")

  top <- head(imp, 10); top <- top[order(top$pct_increase_mse), ]
  open_png("12_feature_importance.png")
  par(mar = c(4.6, 10.5, 3.6, 2.5))
  bp <- barplot(top$pct_increase_mse, horiz = TRUE, names.arg = top$feature, col = NA, border = NA,
                xlim = c(0, max(top$pct_increase_mse) * 1.12), xlab = "Importance (% increase in error when the feature is shuffled)",
                main = "Recent consumption and the time of year drive the forecast", cex.names = 0.78)
  vgrid()
  barplot(top$pct_increase_mse, horiz = TRUE, col = blue, border = surface, add = TRUE, axes = FALSE)
  text(top$pct_increase_mse, bp, sprintf("%.1f", top$pct_increase_mse), pos = 4, cex = 0.75, col = ink)
  subtitle("Top 10 of 15 features in the random forest")
  done("12_feature_importance.png")
} else {
  cat("  (forecast graphs skipped: run r/forecast_models.R first)\n")
}
cat("Done.\n")
