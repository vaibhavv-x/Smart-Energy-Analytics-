# ==============================================================================
# Next-day electricity demand forecasting in R
# Smart Energy Analytics (Batch 30)
#
# Input : hive/cluster_results/daily_features.csv  (feature table built in Hive)
# Output: r/output/model_metrics.csv, test_predictions.csv, feature_importance.csv
#
# Models: naive baseline (tomorrow = today), linear regression (lm), random forest.
# The data is split by time, never shuffled: 70% train, 15% validation, 15% test.
# Run from the project folder:  Rscript r/forecast_models.R
# ==============================================================================

suppressPackageStartupMessages(library(randomForest))

features_file <- file.path("hive", "cluster_results", "daily_features.csv")
if (!file.exists(features_file)) stop("Run the Hive stage first: ", features_file, " not found.")
out_dir <- file.path("r", "output")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

df <- read.csv(features_file, stringsAsFactors = FALSE)
df <- df[order(df$consumption_date), ]
stopifnot(!anyNA(df))

feature_cols <- c(
  "lag_1_energy_kwh", "lag_2_energy_kwh", "lag_7_energy_kwh",
  "rolling_mean_7_kwh", "rolling_std_7_kwh", "rolling_mean_14_kwh",
  "lag_1_avg_power_kw", "lag_1_max_power_kw", "lag_1_avg_voltage_v",
  "lag_1_sub1_kwh", "lag_1_sub2_kwh", "lag_1_sub3_kwh",
  "day_of_week_num", "is_weekend", "month_num"
)

# ---- chronological split ------------------------------------------------------
n <- nrow(df)
n_train <- floor(n * 0.70)
n_val <- floor(n * 0.15)
train <- df[1:n_train, ]
val <- df[(n_train + 1):(n_train + n_val), ]
test <- df[(n_train + n_val + 1):n, ]
cat(sprintf("Days: %d  | train %d (%s to %s) | validation %d (%s to %s) | test %d (%s to %s)\n",
            n, nrow(train), train$consumption_date[1], tail(train$consumption_date, 1),
            nrow(val), val$consumption_date[1], tail(val$consumption_date, 1),
            nrow(test), test$consumption_date[1], tail(test$consumption_date, 1)))

# ---- metrics ------------------------------------------------------------------
metrics <- function(actual, predicted) {
  err <- actual - predicted
  c(MAE = mean(abs(err)),
    RMSE = sqrt(mean(err^2)),
    R2 = 1 - sum(err^2) / sum((actual - mean(actual))^2),
    MAPE = mean(abs(err / actual)) * 100)
}

# ---- models -------------------------------------------------------------------
model_formula <- as.formula(paste("energy_kwh ~", paste(feature_cols, collapse = " + ")))

lm_fit <- lm(model_formula, data = train)

set.seed(42)
rf_fit <- randomForest(model_formula, data = train, ntree = 300, nodesize = 5, importance = TRUE)

predict_all <- function(d) {
  list(Naive_Baseline = d$lag_1_energy_kwh,
       Linear_Regression = as.numeric(predict(lm_fit, d)),
       Random_Forest = as.numeric(predict(rf_fit, d)))
}
val_pred <- predict_all(val)
test_pred <- predict_all(test)

rows <- do.call(rbind, lapply(names(test_pred), function(m) {
  v <- metrics(val$energy_kwh, val_pred[[m]])
  t <- metrics(test$energy_kwh, test_pred[[m]])
  data.frame(model = m,
             val_rmse = round(v[["RMSE"]], 4),
             test_mae = round(t[["MAE"]], 4),
             test_rmse = round(t[["RMSE"]], 4),
             test_r2 = round(t[["R2"]], 4),
             test_mape_pct = round(t[["MAPE"]], 2))
}))
best <- rows$model[which.min(rows$val_rmse)]
rows$selected <- ifelse(rows$model == best, "yes", "")
print(rows, row.names = FALSE)
cat("Selected model (lowest validation RMSE):", best, "\n")

# ---- outputs ------------------------------------------------------------------
write.csv(rows, file.path(out_dir, "model_metrics.csv"), row.names = FALSE)

write.csv(data.frame(date = test$consumption_date,
                     actual_kwh = round(test$energy_kwh, 4),
                     naive_baseline_kwh = round(test_pred$Naive_Baseline, 4),
                     linear_regression_kwh = round(test_pred$Linear_Regression, 4),
                     random_forest_kwh = round(test_pred$Random_Forest, 4)),
          file.path(out_dir, "test_predictions.csv"), row.names = FALSE)

imp <- importance(rf_fit, type = 1)
imp <- data.frame(feature = rownames(imp), pct_increase_mse = round(imp[, 1], 2))
imp <- imp[order(-imp$pct_increase_mse), ]
write.csv(imp, file.path(out_dir, "feature_importance.csv"), row.names = FALSE)

cat("Saved:", file.path(out_dir, c("model_metrics.csv", "test_predictions.csv", "feature_importance.csv")), sep = "\n  ")
cat("\n")
