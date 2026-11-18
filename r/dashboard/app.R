# ==============================================================================
# Smart Energy Analytics (Batch 30): interactive dashboard in R Shiny
#
# Reads the results produced on the Hadoop cluster (MapReduce job outputs and
# Hive query results) and by the R forecasting script. It does not need Hadoop
# to be running.
#
# Run from the project folder:
#   Rscript -e 'shiny::runApp("r/dashboard", launch.browser = TRUE)'
# or:
#   bash run_on_mac.sh dashboard
# ==============================================================================

suppressPackageStartupMessages(library(shiny))

# runApp() sets the working directory to this folder; the project is two levels up.
PROJECT <- normalizePath(file.path(getwd(), "..", ".."))
pp <- function(...) file.path(PROJECT, ...)

# ---------------------------------------------------------------- data
hive_csv <- function(n) {
  d <- read.csv(pp("hive", "cluster_results", sprintf("q%02d.csv", n)), stringsAsFactors = FALSE)
  names(d) <- sub("^.*\\.", "", names(d))
  d
}
need <- c(pp("hive", "cluster_results", "q01.csv"), pp("hadoop", "mapreduce_yarn_hourly_output.txt"),
          pp("r", "output", "model_metrics.csv"))
if (!all(file.exists(need))) stop("Results not found. Run  bash run_on_mac.sh  first.")

daily <- hive_csv(1); daily$date <- as.Date(daily$consumption_date)
monthly <- hive_csv(2)
seasonal <- hive_csv(7); seasonal <- seasonal[order(seasonal$month_num), ]
week <- hive_csv(6)
sub <- hive_csv(8)
yoy <- hive_csv(9)
heavy <- hive_csv(10)
bands <- hive_csv(11); bands <- bands[order(bands$band), ]
quality <- hive_csv(12)
top_days <- hive_csv(5)

hourly <- read.delim(pp("hadoop", "mapreduce_yarn_hourly_output.txt"), header = FALSE,
                     col.names = c("hour", "kwh", "readings", "avg_kw", "peak_kw"))
hourly <- hourly[order(hourly$hour), ]
mr_daily <- read.delim(pp("hadoop", "mapreduce_yarn_daily_output.txt"), header = FALSE,
                       col.names = c("date", "kwh", "readings"))

metrics <- read.csv(pp("r", "output", "model_metrics.csv"), stringsAsFactors = FALSE)
pred <- read.csv(pp("r", "output", "test_predictions.csv"), stringsAsFactors = FALSE); pred$date <- as.Date(pred$date)
imp <- read.csv(pp("r", "output", "feature_importance.csv"), stringsAsFactors = FALSE)

# The 12 HiveQL queries, for the "Hive queries" page
hql <- paste(readLines(pp("hive", "queries.hql"), warn = FALSE), collapse = "\n")
q_match <- gregexpr("(?s)-- Query (\\d+): ([^\n]+)\n(.*?);", hql, perl = TRUE)
q_blocks <- regmatches(hql, q_match)[[1]]
queries <- lapply(q_blocks, function(b) {
  num <- as.integer(sub("(?s)^-- Query (\\d+):.*", "\\1", b, perl = TRUE))
  title <- sub("(?s)^-- Query \\d+: ([^\n]+)\n.*", "\\1", b, perl = TRUE)
  body <- sub("^-- Query \\d+: [^\n]+\n", "", b, perl = TRUE)
  lines <- strsplit(body, "\n")[[1]]
  sql <- paste(trimws(lines[!grepl("^\\s*--", lines)], which = "right"), collapse = "\n")
  list(num = num, title = title, sql = trimws(sql))
})
query_choices <- setNames(sapply(queries, `[[`, "num"), sapply(queries, function(q) sprintf("Q%d: %s", q$num, q$title)))

# ---------------------------------------------------------------- headline numbers
peak <- hourly[which.max(hourly$avg_kw), ]; low <- hourly[which.min(hourly$avg_kw), ]
weekday <- week$avg_daily_energy_kwh[week$day_category == "Weekday"]
weekend <- week$avg_daily_energy_kwh[week$day_category == "Weekend"]
best <- metrics[metrics$selected == "yes", ]
base <- metrics[metrics$model == "Naive_Baseline", ]
model_label <- c(Naive_Baseline = "Naive baseline", Linear_Regression = "Linear regression", Random_Forest = "Random forest")

# ---------------------------------------------------------------- chart style
surface <- "#ffffff"; ink <- "#0b0b0b"; ink2 <- "#52514e"; grid <- "#e4e3df"
blue <- "#2a78d6"; orange <- "#eb6834"; aqua <- "#1baf7a"; yellow <- "#eda100"
blue_light <- "#9ec5f4"; blue_dark <- "#184f95"
year_cols <- c(`2007` = blue, `2008` = orange, `2009` = aqua, `2010` = yellow)

style <- function(left = 4.6) {
  par(mar = c(4.2, left, 1.2, 1.2), bg = surface, fg = ink2, col.axis = ink2, col.lab = ink2,
      las = 1, bty = "n", cex.axis = 0.9, cex.lab = 0.95, mgp = c(3, 0.7, 0), tcl = -0.25)
}
hgrid <- function() abline(h = axTicks(2), col = grid)
vgrid <- function() abline(v = axTicks(1), col = grid)
bars <- function(values, labels, ylab, fmt = "%.1f", col = blue, highlight = NULL) {
  style()
  cols <- rep(col, length(values)); if (!is.null(highlight)) cols[highlight] <- orange
  bp <- barplot(values, names.arg = labels, col = NA, border = NA, ylim = c(0, max(values) * 1.18), ylab = ylab, cex.names = 0.8)
  hgrid()
  barplot(values, col = cols, border = surface, add = TRUE, axes = FALSE)
  if (!is.null(fmt)) text(bp, values, sprintf(fmt, values), pos = 3, cex = 0.85, col = ink)
  invisible(bp)
}

# ---------------------------------------------------------------- UI
kpi <- function(value, label) div(class = "kpi", div(class = "kpi-value", value), div(class = "kpi-label", label))
card <- function(title, subtitle, ...) div(class = "card", h4(title), if (!is.null(subtitle)) p(class = "sub", subtitle), ...)

ui <- fluidPage(
  title = "Smart Energy Analytics dashboard",
  tags$head(tags$style(HTML("
    body { background: #f4f6f8; color: #0b0b0b; font-family: -apple-system, 'Helvetica Neue', Arial, sans-serif; }
    .header { background: #17332e; color: #fff; padding: 18px 24px; margin: 0 -15px 18px; }
    .header h2 { margin: 0 0 4px; font-weight: 700; }
    .header p { margin: 0; color: #cfe3df; }
    .nav-tabs { border-bottom: 1px solid #d5dbe0; }
    .nav-tabs > li > a { color: #52514e; font-weight: 600; }
    .nav-tabs > li.active > a, .nav-tabs > li.active > a:focus { color: #17332e; }
    .card { background: #fff; border-radius: 10px; padding: 16px 18px 10px; margin: 16px 0; box-shadow: 0 1px 3px rgba(0,0,0,.08); }
    .card h4 { margin: 0 0 4px; font-weight: 700; }
    .card .sub { color: #52514e; margin: 0 0 8px; font-size: 13px; }
    .kpis { display: flex; flex-wrap: wrap; gap: 14px; margin-top: 16px; }
    .kpi { flex: 1 1 170px; background: #fff; border-radius: 10px; padding: 14px 16px; box-shadow: 0 1px 3px rgba(0,0,0,.08); }
    .kpi-value { font-size: 26px; font-weight: 700; color: #17332e; }
    .kpi-label { color: #52514e; font-size: 13px; margin-top: 2px; }
    pre.sql { background: #f7f7f5; border: 1px solid #e4e3df; font-size: 12px; white-space: pre-wrap; }
    table.table { font-size: 13px; }
    .source { color: #52514e; font-size: 12px; }
  "))),
  div(class = "header",
      h2("Smart Energy Analytics"),
      p("Household electricity consumption, 2006 to 2010  |  Hadoop HDFS, MapReduce and Hive, visualized in R  |  Batch 30: Vaibhav, Saubhagya Kashyap")),
  tabsetPanel(
    tabPanel("Overview",
      div(class = "kpis",
          kpi("2,075,259", "one-minute readings in HDFS"),
          kpi(format(nrow(daily), big.mark = ","), "valid days analysed"),
          kpi(sprintf("%02d:00", peak$hour), sprintf("peak hour, %.2f kW on average", peak$avg_kw)),
          kpi(sprintf("+%.1f%%", (weekend / weekday - 1) * 100), "weekend use vs weekday"),
          kpi(sprintf("%.2f kWh", best$test_mae), sprintf("forecast error (baseline %.2f)", base$test_mae))),
      card("Daily electricity consumption", "Drag the slider to zoom in on a period. Source: Hive query 1 (valid days only).",
           sliderInput("range", NULL, min = min(daily$date), max = max(daily$date),
                       value = c(min(daily$date), max(daily$date)), timeFormat = "%b %Y", width = "100%"),
           checkboxInput("ma", "Show 30-day average", TRUE),
           plotOutput("daily_plot", height = "380px"),
           uiOutput("daily_summary"))
    ),
    tabPanel("Time of day",
      fluidRow(
        column(7, card("Average power in each hour of the day",
                       sprintf("Peak at %02d:00 (%.2f kW), lowest at %02d:00 (%.2f kW). Source: MapReduce job 2 on YARN, %s readings.",
                               peak$hour, peak$avg_kw, low$hour, low$avg_kw, format(sum(hourly$readings), big.mark = ",")),
                       radioButtons("hour_measure", NULL, inline = TRUE,
                                    choices = c("Average power (kW)" = "avg_kw", "Highest single reading (kW)" = "peak_kw")),
                       plotOutput("hourly_plot", height = "380px"))),
        column(5, card("Share of energy by time of day", "Source: Hive query 11.",
                       plotOutput("bands_plot", height = "300px"),
                       tableOutput("bands_table")))
      )
    ),
    tabPanel("Seasons and weekends",
      fluidRow(
        column(6, card("Average day in each calendar month", "Source: Hive query 7.",
                       plotOutput("season_plot", height = "330px"))),
        column(6, card("Weekday against weekend", sprintf("Weekends use %.1f%% more. Source: Hive query 6.", (weekend / weekday - 1) * 100),
                       plotOutput("week_plot", height = "330px")))
      ),
      card("Monthly consumption by year", "Tick the years to compare. Source: Hive query 2.",
           checkboxGroupInput("years", NULL, choices = names(year_cols), selected = names(year_cols), inline = TRUE),
           plotOutput("years_plot", height = "340px"))
    ),
    tabPanel("What uses the energy",
      fluidRow(
        column(6, card("Share of energy by sub-meter", "Source: Hive query 8, over 1,420 valid days.",
                       plotOutput("sub_plot", height = "330px"))),
        column(6, card("Days above 40 kWh, per year", "2006 has only 15 days of data. Source: Hive query 10.",
                       plotOutput("heavy_plot", height = "330px")))
      ),
      fluidRow(
        column(6, card("Missing readings per year", "Counted on the raw table of 2,075,259 rows. Source: Hive query 12.",
                       plotOutput("quality_plot", height = "300px"))),
        column(6, card("Ten highest-consumption days", "Source: Hive query 5.", tableOutput("top_table")))
      )
    ),
    tabPanel("Forecast",
      div(class = "kpis",
          lapply(seq_len(nrow(metrics)), function(i) {
            r <- metrics[i, ]
            kpi(sprintf("%.2f kWh", r$test_mae),
                sprintf("%s: mean error%s", model_label[[r$model]], if (r$selected == "yes") " (selected)" else ""))
          })),
      card("Actual against predicted, test period", sprintf("%s to %s. Models trained in R on features built in Hive.",
                                                            format(min(pred$date), "%d %b %Y"), format(max(pred$date), "%d %b %Y")),
           checkboxGroupInput("models", NULL, inline = TRUE,
                              choices = c("Random forest" = "random_forest_kwh", "Linear regression" = "linear_regression_kwh",
                                          "Naive baseline" = "naive_baseline_kwh"),
                              selected = "random_forest_kwh"),
           plotOutput("pred_plot", height = "380px")),
      fluidRow(
        column(6, card("Model comparison on the test period", "Lower error is better; R² closer to 1 is better.",
                       tableOutput("metrics_table"))),
        column(6, card("Most useful inputs (random forest)", "Increase in error when a feature is shuffled.",
                       plotOutput("imp_plot", height = "330px")))
      )
    ),
    tabPanel("Hive queries",
      card("Results of the 12 HiveQL queries", "Each query ran on HiveServer2 as MapReduce jobs on YARN. Pick one to see its SQL and result.",
           selectInput("q", NULL, choices = query_choices, width = "100%"),
           tags$pre(class = "sql", textOutput("q_sql")),
           div(style = "max-height: 420px; overflow: auto;", tableOutput("q_table")),
           p(class = "source", textOutput("q_rows", inline = TRUE)))
    ),
    tabPanel("About",
      card("How this dashboard is produced", NULL,
           tags$ol(
             tags$li("The raw file (2,075,259 one-minute readings, 126.8 MB) is stored in HDFS."),
             tags$li("Two Hadoop MapReduce jobs on YARN compute the daily totals and the hour-of-day profile."),
             tags$li("Apache Hive builds the daily (ORC) and hourly (Parquet) tables from the raw data, answers 12 queries, and builds the forecasting features."),
             tags$li("R trains the forecasting models (lm, randomForest)."),
             tags$li("This R Shiny dashboard reads those saved results and draws every chart.")),
           tags$table(class = "table",
             tags$tr(tags$th("Layer"), tags$th("Tools")),
             tags$tr(tags$td("Storage"), tags$td("Hadoop HDFS 3.3.6")),
             tags$tr(tags$td("Processing"), tags$td("Hadoop MapReduce and YARN 3.3.6, Apache Hive 4.0.1")),
             tags$tr(tags$td("Modelling and visualization"), tags$td("R 4.6 (lm, randomForest, Shiny)")))),
      card("Check: MapReduce against Hive", NULL, uiOutput("check"))
    )
  )
)

# ---------------------------------------------------------------- server
server <- function(input, output, session) {
  d_range <- reactive(daily[daily$date >= input$range[1] & daily$date <= input$range[2], ])

  output$daily_plot <- renderPlot({
    d <- d_range(); req(nrow(d) > 1)
    style()
    plot(d$date, d$daily_energy_kwh, type = "n", xlab = "", ylab = "Energy (kWh per day)", ylim = c(0, max(d$daily_energy_kwh) * 1.05))
    hgrid()
    lines(d$date, d$daily_energy_kwh, col = blue_light, lwd = 1)
    if (input$ma && nrow(d) >= 30) lines(d$date, stats::filter(d$daily_energy_kwh, rep(1 / 30, 30), sides = 1), col = blue_dark, lwd = 2.2)
    legend("topright", c("Daily energy", if (input$ma) "30-day average"), col = c(blue_light, if (input$ma) blue_dark),
           lwd = c(1.5, 2.5), bty = "n", text.col = ink)
  }, res = 110)
  output$daily_summary <- renderUI({
    d <- d_range()
    p(class = "source", sprintf("%s days shown: average %.1f kWh a day, highest %.1f kWh on %s, lowest %.1f kWh on %s.",
                                format(nrow(d), big.mark = ","), mean(d$daily_energy_kwh),
                                max(d$daily_energy_kwh), format(d$date[which.max(d$daily_energy_kwh)], "%d %b %Y"),
                                min(d$daily_energy_kwh), format(d$date[which.min(d$daily_energy_kwh)], "%d %b %Y")))
  })

  output$hourly_plot <- renderPlot({
    v <- hourly[[input$hour_measure]]
    bars(v, sprintf("%02d", hourly$hour), if (input$hour_measure == "avg_kw") "Average power (kW)" else "Highest reading (kW)",
         fmt = NULL, highlight = which.max(v))
    mtext("Hour of day", side = 1, line = 2.6, col = ink2, cex = 0.95)
  }, res = 110)
  output$bands_plot <- renderPlot(bars(bands$share_pct, sub("^[0-9] ", "", sub(" \\(", "\n(", bands$band)),
                                       "Share of energy (%)", fmt = "%.1f%%", highlight = which.max(bands$share_pct)), res = 110)
  output$bands_table <- renderTable(data.frame(Band = sub("^[0-9] ", "", bands$band), `Energy (kWh)` = format(bands$total_kwh, big.mark = ","),
                                               `Share (%)` = bands$share_pct, check.names = FALSE), striped = TRUE)

  output$season_plot <- renderPlot(bars(seasonal$seasonal_avg_daily_kwh, substr(seasonal$month_name, 1, 3), "Average energy (kWh per day)",
                                        highlight = which.max(seasonal$seasonal_avg_daily_kwh)), res = 110)
  output$week_plot <- renderPlot(bars(c(weekday, weekend), c("Weekday", "Weekend"), "Average energy (kWh per day)", fmt = "%.2f"), res = 110)
  output$years_plot <- renderPlot({
    req(length(input$years) > 0)
    m <- monthly[monthly$year_num %in% as.integer(input$years), ]
    style()
    plot(NA, xlim = c(1, 12), ylim = c(0, max(monthly$avg_daily_kwh) * 1.08), xaxt = "n", xlab = "", ylab = "Average energy (kWh per day)")
    axis(1, at = 1:12, labels = month.abb, tick = FALSE)
    hgrid()
    for (y in input$years) {
      r <- m[m$year_num == as.integer(y), ]; r <- r[order(r$month_num), ]
      lines(r$month_num, r$avg_daily_kwh, col = year_cols[[y]], lwd = 2)
      points(r$month_num, r$avg_daily_kwh, col = year_cols[[y]], pch = 19, cex = 0.8)
    }
    legend("top", legend = input$years, col = year_cols[input$years], lwd = 2.5, pch = 19, horiz = TRUE, bty = "n", text.col = ink)
  }, res = 110)

  output$sub_plot <- renderPlot({
    share <- c("Kitchen" = sub$kitchen_percentage, "Laundry" = sub$laundry_percentage,
               "Water heater,\nair conditioner" = sub$climate_water_percentage, "Not sub-metered" = sub$remainder_percentage)
    share <- sort(share)
    style(left = 9.5)
    bp <- barplot(share, horiz = TRUE, col = NA, border = NA, xlim = c(0, max(share) * 1.18), xlab = "Share of total energy (%)")
    vgrid()
    barplot(share, horiz = TRUE, col = blue, border = surface, add = TRUE, axes = FALSE, names.arg = rep("", length(share)))
    text(share, bp, sprintf("%.1f%%", share), pos = 4, cex = 0.85, col = ink)
  }, res = 110)
  output$heavy_plot <- renderPlot({
    h <- heavy[heavy$year_num >= 2007, ]
    bars(h$high_days_pct, h$year_num, "Days above 40 kWh (%)", fmt = "%.1f%%")
  }, res = 110)
  output$quality_plot <- renderPlot(bars(quality$missing_pct, quality$year_num, "Missing readings (%)", fmt = "%.2f%%",
                                         highlight = which.max(quality$missing_pct)), res = 110)
  output$top_table <- renderTable(data.frame(Date = top_days$consumption_date, Day = top_days$day_of_week,
                                             `Energy (kWh)` = top_days$total_energy_kwh, `Peak power (kW)` = top_days$peak_power_kw,
                                             check.names = FALSE), striped = TRUE)

  output$pred_plot <- renderPlot({
    style()
    plot(pred$date, pred$actual_kwh, type = "n", xaxt = "n", xlab = "", ylab = "Energy (kWh per day)", ylim = c(0, max(pred$actual_kwh) * 1.08))
    ticks <- seq(as.Date("2010-05-01"), max(pred$date), by = "month")
    axis(1, at = ticks, labels = format(ticks, "%b %Y"), tick = FALSE)
    hgrid()
    lines(pred$date, pred$actual_kwh, col = ink2, lwd = 1.4)
    cols <- c(random_forest_kwh = blue, linear_regression_kwh = orange, naive_baseline_kwh = aqua)
    labs <- c(random_forest_kwh = "Random forest", linear_regression_kwh = "Linear regression", naive_baseline_kwh = "Naive baseline")
    for (m in input$models) lines(pred$date, pred[[m]], col = cols[[m]], lwd = 2)
    legend("top", c("Actual", labs[input$models]), col = c(ink2, cols[input$models]), lwd = 2.5, horiz = TRUE, bty = "n", text.col = ink)
  }, res = 110)
  output$metrics_table <- renderTable(data.frame(
    Model = model_label[metrics$model], `MAE (kWh)` = sprintf("%.2f", metrics$test_mae), `RMSE (kWh)` = sprintf("%.2f", metrics$test_rmse),
    `R²` = sprintf("%.2f", metrics$test_r2), `MAPE` = sprintf("%.1f%%", metrics$test_mape_pct),
    Selected = ifelse(metrics$selected == "yes", "yes", ""), check.names = FALSE), striped = TRUE)
  output$imp_plot <- renderPlot({
    t <- head(imp, 10); t <- t[order(t$pct_increase_mse), ]
    style(left = 10.5)
    bp <- barplot(t$pct_increase_mse, horiz = TRUE, names.arg = t$feature, col = NA, border = NA,
                  xlim = c(0, max(t$pct_increase_mse) * 1.15), xlab = "Importance", cex.names = 0.8)
    vgrid()
    barplot(t$pct_increase_mse, horiz = TRUE, col = blue, border = surface, add = TRUE, axes = FALSE, names.arg = rep("", nrow(t)))
    text(t$pct_increase_mse, bp, sprintf("%.1f", t$pct_increase_mse), pos = 4, cex = 0.8, col = ink)
  }, res = 110)

  sel_query <- reactive(queries[[which(sapply(queries, `[[`, "num") == as.integer(input$q))]])
  sel_result <- reactive(hive_csv(as.integer(input$q)))
  output$q_sql <- renderText(sel_query()$sql)
  output$q_table <- renderTable(head(sel_result(), 200), striped = TRUE)
  output$q_rows <- renderText({
    n <- nrow(sel_result())
    sprintf("%s rows returned by Hive%s. File: hive/cluster_results/q%02d.csv", format(n, big.mark = ","),
            if (n > 200) ", first 200 shown" else "", as.integer(input$q))
  })

  output$check <- renderUI({
    mr <- mr_daily
    mr$iso <- format(as.Date(mr$date, format = "%d/%m/%Y"), "%Y-%m-%d")
    j <- merge(mr, daily, by.x = "iso", by.y = "consumption_date")
    tags$p(sprintf("The MapReduce job and Hive computed the daily energy independently from the same raw file in HDFS. On all %s valid days they agree: largest difference %.4f kWh, reading counts identical on %s days.",
                   format(nrow(j), big.mark = ","), max(abs(j$kwh - j$daily_energy_kwh)),
                   format(sum(j$readings == j$reading_count), big.mark = ",")))
  })
}

shinyApp(ui, server)
