import os
import json
import pandas as pd
import numpy as np
import plotly.express as px
import plotly.graph_objects as go
import streamlit as st

# ==============================================================================
# 1. PAGE CONFIGURATION & METADATA
# ==============================================================================
st.set_page_config(
    page_title="Smart Energy Analytics | Batch 30 Big Data Project",
    page_icon="⚡",
    layout="wide",
    initial_sidebar_state="expanded"
)

# Custom Styling
st.markdown("""
<style>
    .main-title {
        font-size: 2.2rem;
        font-weight: 800;
        color: #0f766e;
        margin-bottom: 0.2rem;
    }
    .sub-title {
        font-size: 1.05rem;
        color: #475569;
        margin-bottom: 1.5rem;
    }
    .metric-card {
        background-color: #f8fafc;
        border: 1px solid #e2e8f0;
        border-radius: 8px;
        padding: 1rem;
        text-align: center;
    }
    .badge-pill {
        display: inline-block;
        padding: 0.25rem 0.6rem;
        font-size: 0.8rem;
        font-weight: 600;
        border-radius: 9999px;
        background-color: #ccfbf1;
        color: #115e59;
        margin-right: 0.4rem;
    }
</style>
""", unsafe_allow_html=True)

# ==============================================================================
# 2. CACHED DATA LOADING
# ==============================================================================
@st.cache_data
def load_project_data():
    base_dir = os.path.dirname(os.path.abspath(__file__))
    
    # 1. Daily energy
    daily_path = os.path.join(base_dir, "data", "processed", "daily_energy_consumption.csv")
    if not os.path.exists(daily_path):
        daily_path = os.path.join(base_dir, "dashboard", "power_bi_exports", "fact_daily_energy.csv")
    daily_df = pd.read_csv(daily_path)
    daily_df["Date"] = pd.to_datetime(daily_df["Date_ISO" if "Date_ISO" in daily_df.columns else "Date"])
    daily_df = daily_df.sort_values("Date").reset_index(drop=True)
    daily_valid = daily_df[daily_df["Is_valid_day"] == 1].copy()
    daily_valid["Rolling_7D"] = daily_valid["Energy_kWh"].rolling(7, min_periods=3).mean()
    daily_valid["Rolling_30D"] = daily_valid["Energy_kWh"].rolling(30, min_periods=7).mean()

    # 2. Hourly energy
    hourly_path = os.path.join(base_dir, "data", "processed", "hourly_energy_consumption.csv")
    hourly_df = pd.read_csv(hourly_path)
    if "Datetime_hour" in hourly_df.columns:
        hourly_df["Datetime_hour"] = pd.to_datetime(hourly_df["Datetime_hour"])
        hourly_df["Day_of_week"] = hourly_df["Datetime_hour"].dt.day_name()
    elif "Date" in hourly_df.columns:
        hourly_df["Datetime_hour"] = pd.to_datetime(hourly_df["Date"] + " " + hourly_df["Hour"].astype(str) + ":00:00")
        hourly_df["Day_of_week"] = hourly_df["Datetime_hour"].dt.day_name()

    # 3. Test Predictions
    preds_path = os.path.join(base_dir, "forecasting", "test_predictions.csv")
    preds_df = pd.read_csv(preds_path)
    preds_df["Date"] = pd.to_datetime(preds_df["Date"])

    # 4. Evaluation Metrics
    metrics_path = os.path.join(base_dir, "forecasting", "evaluation_metrics.json")
    with open(metrics_path, "r", encoding="utf-8") as f:
        metrics_dict = json.load(f)

    # 5. Cleaning Summary
    summary_path = os.path.join(base_dir, "data", "processed", "cleaning_summary.json")
    summary_dict = {}
    if os.path.exists(summary_path):
        with open(summary_path, "r", encoding="utf-8") as f:
            summary_dict = json.load(f)

    return daily_df, daily_valid, hourly_df, preds_df, metrics_dict, summary_dict

daily_df, daily_valid, hourly_df, preds_df, metrics_dict, summary_dict = load_project_data()

# ==============================================================================
# 3. SIDEBAR NAVIGATION & FILTERS
# ==============================================================================
st.sidebar.image("https://img.icons8.com/fluency/96/flash-on.png", width=64)
st.sidebar.markdown("### **Smart Energy Analytics**")
st.sidebar.markdown(
    "<span class='badge-pill'>Batch 30</span>"
    "<span class='badge-pill'>UN SDG 7</span>"
    "<span class='badge-pill'>Hadoop · Hive · Spark</span>",
    unsafe_allow_html=True
)

st.sidebar.markdown("---")
nav_choice = st.sidebar.radio(
    "**Dashboard Navigation**",
    [
        "⚡ Energy Overview & KPIs",
        "🔍 Deep-Dive Consumption Analysis",
        "🤖 Machine Learning Forecasting",
        "🌿 Sustainability & SDG 7 Insights",
        "🐘 Hadoop & Hive Cluster Results",
        "📚 Project & Big Data Architecture"
    ]
)

st.sidebar.markdown("---")
st.sidebar.markdown("#### **Interactive Parameters**")
min_date = daily_valid["Date"].min().date()
max_date = daily_valid["Date"].max().date()
selected_date_range = st.sidebar.date_input(
    "Filter Date Range",
    value=[min_date, max_date],
    min_value=min_date,
    max_value=max_date
)

tariff_eur = st.sidebar.slider(
    "Electricity Tariff (€ / kWh)",
    min_value=0.10,
    max_value=0.50,
    value=0.20,
    step=0.01,
    help="Configurable residential electricity rate for cost estimation."
)

st.sidebar.markdown("---")
st.sidebar.caption(
    "**Project Team (Batch 30):**\n"
    "- Vaibhav (AP23110010425)\n"
    "- Saubhagya Kashyap (AP23110010439)\n\n"
    "**Course:** Big Data Analytics (BDA)"
)

# Apply Date Filter
if len(selected_date_range) == 2:
    start_d, end_d = selected_date_range
    filtered_daily = daily_valid[
        (daily_valid["Date"].dt.date >= start_d) & (daily_valid["Date"].dt.date <= end_d)
    ]
else:
    filtered_daily = daily_valid

# ==============================================================================
# TAB 1: ENERGY OVERVIEW & KPIS
# ==============================================================================
if nav_choice == "⚡ Energy Overview & KPIs":
    st.markdown('<div class="main-title">⚡ Smart Energy Consumption Overview</div>', unsafe_allow_html=True)
    st.markdown('<div class="sub-title">Big Data Analytics on 2,075,259 high-frequency smart meter readings (UCI Household Power Consumption)</div>', unsafe_allow_html=True)

    # KPI Row
    total_kwh = filtered_daily["Energy_kWh"].sum()
    total_cost = total_kwh * tariff_eur
    avg_kwh = filtered_daily["Energy_kWh"].mean()
    max_kwh = filtered_daily["Energy_kWh"].max()
    peak_power = filtered_daily["Max_power_kW"].max()

    col1, col2, col3, col4, col5 = st.columns(5)
    with col1:
        st.metric("Total Energy", f"{total_kwh:,.1f} kWh", delta=f"{total_kwh/1000:.2f} MWh")
    with col2:
        st.metric("Average Daily", f"{avg_kwh:.2f} kWh/day")
    with col3:
        st.metric("Peak Power", f"{peak_power:.2f} kW")
    with col4:
        st.metric("Monitored Days", f"{len(filtered_daily):,} days")
    with col5:
        st.metric("Estimated Cost", f"€{total_cost:,.2f}", delta=f"@ €{tariff_eur:.2f}/kWh")

    st.markdown("---")

    # Time-series Line Chart
    st.markdown("#### **Historical Daily Electricity Consumption Trend (2006 – 2010)**")
    show_ma7 = st.checkbox("Show 7-Day Moving Average", value=True)
    show_ma30 = st.checkbox("Show 30-Day Moving Average", value=True)

    fig_trend = go.Figure()
    fig_trend.add_trace(go.Scatter(
        x=filtered_daily["Date"],
        y=filtered_daily["Energy_kWh"],
        mode="lines",
        name="Daily Energy (kWh)",
        line=dict(color="#93c5fd", width=1.0),
        opacity=0.7
    ))

    if show_ma7 and "Rolling_7D" in filtered_daily.columns:
        fig_trend.add_trace(go.Scatter(
            x=filtered_daily["Date"],
            y=filtered_daily["Rolling_7D"],
            mode="lines",
            name="7-Day Moving Avg",
            line=dict(color="#2563eb", width=2.0)
        ))

    if show_ma30 and "Rolling_30D" in filtered_daily.columns:
        fig_trend.add_trace(go.Scatter(
            x=filtered_daily["Date"],
            y=filtered_daily["Rolling_30D"],
            mode="lines",
            name="30-Day Moving Avg",
            line=dict(color="#1e3a8a", width=2.5)
        ))

    fig_trend.add_hline(
        y=avg_kwh,
        line_dash="dash",
        line_color="#ef4444",
        annotation_text=f"Mean: {avg_kwh:.2f} kWh/day",
        annotation_position="top right"
    )

    fig_trend.update_layout(
        height=420,
        margin=dict(l=20, r=20, t=30, b=20),
        xaxis_title="Date",
        yaxis_title="Energy Consumption (kWh)",
        legend=dict(orientation="h", yanchor="bottom", y=1.02, xanchor="right", x=1),
        hovermode="x unified"
    )
    st.plotly_chart(fig_trend, use_container_width=True)

    # Two column monthly & diurnal breakdown
    col_left, col_right = st.columns(2)

    with col_left:
        st.markdown("#### **Monthly Total Energy (kWh)**")
        monthly_df = filtered_daily.groupby(["Year", "Month_name", "Month"])["Energy_kWh"].sum().reset_index()
        monthly_df["YearMonth"] = monthly_df["Year"].astype(str) + " " + monthly_df["Month_name"].str.slice(0, 3)
        monthly_df = monthly_df.sort_values(["Year", "Month"])

        fig_month = px.bar(
            monthly_df,
            x="YearMonth",
            y="Energy_kWh",
            color="Year",
            title="Monthly Energy Aggregate (kWh)",
            color_continuous_scale="Blues"
        )
        fig_month.update_layout(height=350, margin=dict(l=20, r=20, t=40, b=20), xaxis_title="Month", yaxis_title="Total kWh")
        st.plotly_chart(fig_month, use_container_width=True)

    with col_right:
        st.markdown("#### **24-Hour Diurnal Demand Profile**")
        diurnal = hourly_df.groupby("Hour")["Energy_kWh"].agg(["mean", "min", "max"]).reset_index()
        
        fig_diurnal = go.Figure()
        fig_diurnal.add_trace(go.Scatter(
            x=diurnal["Hour"],
            y=diurnal["mean"],
            mode="lines+markers",
            name="Average Hourly (kWh)",
            line=dict(color="#f97316", width=3)
        ))
        fig_diurnal.add_trace(go.Scatter(
            x=diurnal["Hour"],
            y=diurnal["max"],
            mode="lines",
            line=dict(width=0),
            showlegend=False
        ))
        fig_diurnal.add_trace(go.Scatter(
            x=diurnal["Hour"],
            y=diurnal["min"],
            mode="lines",
            fill="tonexty",
            fillcolor="rgba(249, 115, 22, 0.15)",
            line=dict(width=0),
            name="Min-Max Range"
        ))
        fig_diurnal.update_layout(
            height=350,
            margin=dict(l=20, r=20, t=40, b=20),
            xaxis=dict(tickmode="linear", tick0=0, dtick=2, title="Hour of Day (0–23)"),
            yaxis_title="Hourly Energy (kWh)",
            legend=dict(orientation="h", yanchor="bottom", y=1.02, xanchor="right", x=1)
        )
        st.plotly_chart(fig_diurnal, use_container_width=True)

# ==============================================================================
# TAB 2: DEEP-DIVE CONSUMPTION ANALYSIS
# ==============================================================================
elif nav_choice == "🔍 Deep-Dive Consumption Analysis":
    st.markdown('<div class="main-title">🔍 Deep-Dive Consumption Analysis</div>', unsafe_allow_html=True)
    st.markdown('<div class="sub-title">Multi-dimensional behavioral analytics, sub-metering disaggregation, and diurnal load profiling</div>', unsafe_allow_html=True)

    col1, col2 = st.columns([1, 1])

    with col1:
        st.markdown("#### **Weekday vs. Weekend Consumption Distribution**")
        filtered_daily["Day_Type"] = np.where(filtered_daily["Is_weekend"] == 1, "Weekend (Sat–Sun)", "Weekday (Mon–Fri)")
        fig_box = px.box(
            filtered_daily,
            x="Day_Type",
            y="Energy_kWh",
            color="Day_Type",
            color_discrete_map={"Weekday (Mon–Fri)": "#3b82f6", "Weekend (Sat–Sun)": "#8b5cf6"},
            points="outliers",
            notched=True
        )
        fig_box.update_layout(height=380, margin=dict(l=20, r=20, t=20, b=20), showlegend=False, yaxis_title="Daily Energy (kWh)")
        st.plotly_chart(fig_box, use_container_width=True)

        # Metrics comparison
        wknd_mean = filtered_daily[filtered_daily["Is_weekend"] == 1]["Energy_kWh"].mean()
        wkday_mean = filtered_daily[filtered_daily["Is_weekend"] == 0]["Energy_kWh"].mean()
        surge_pct = ((wknd_mean - wkday_mean) / wkday_mean) * 100
        st.info(f"💡 **Weekend Surge:** Average weekend consumption (**{wknd_mean:.2f} kWh/day**) is **+{surge_pct:.1f}% higher** than weekdays (**{wkday_mean:.2f} kWh/day**) due to domestic occupancy and weekend appliance usage.")

    with col2:
        st.markdown("#### **Sub-Metering End-Use Disaggregation**")
        sub1_tot = filtered_daily["Sub_metering_1_kWh"].sum()
        sub2_tot = filtered_daily["Sub_metering_2_kWh"].sum()
        sub3_tot = filtered_daily["Sub_metering_3_kWh"].sum()
        rem_tot = filtered_daily["Sub_metering_remainder_kWh"].sum()

        sub_df = pd.DataFrame({
            "Circuit": ["Kitchen (Sub 1)", "Laundry (Sub 2)", "Climate & Water (Sub 3)", "Unmetered Remainder"],
            "Energy_kWh": [sub1_tot, sub2_tot, sub3_tot, rem_tot],
            "Description": [
                "Dishwasher, Microwave, Oven",
                "Washing Machine, Dryer, Fridge",
                "Water Heater & Air Conditioner",
                "Lighting, Electronics, Plug Loads"
            ]
        })
        fig_pie = px.pie(
            sub_df,
            names="Circuit",
            values="Energy_kWh",
            color="Circuit",
            color_discrete_map={
                "Kitchen (Sub 1)": "#f97316",
                "Laundry (Sub 2)": "#10b981",
                "Climate & Water (Sub 3)": "#6366f1",
                "Unmetered Remainder": "#94a3b8"
            },
            hole=0.45
        )
        fig_pie.update_traces(textposition="inside", textinfo="percent+label")
        fig_pie.update_layout(height=380, margin=dict(l=20, r=20, t=20, b=20), showlegend=False)
        st.plotly_chart(fig_pie, use_container_width=True)
        st.caption("Sub 3 (Climate Control & Water Heating) is the dominant sub-metered thermal circuit, consuming ~35.5% of total household energy.")

    st.markdown("---")
    st.markdown("#### **Diurnal Load Curves Across Days of the Week**")
    day_order = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    dow_hourly = hourly_df.groupby(["Day_of_week", "Hour"])["Energy_kWh"].mean().reset_index()

    fig_dow = go.Figure()
    for dow in day_order:
        subset = dow_hourly[dow_hourly["Day_of_week"] == dow]
        is_wknd = dow in ["Saturday", "Sunday"]
        fig_dow.add_trace(go.Scatter(
            x=subset["Hour"],
            y=subset["Energy_kWh"],
            mode="lines",
            name=dow,
            line=dict(
                width=3.0 if is_wknd else 1.5,
                dash="solid" if is_wknd else "dot"
            )
        ))

    fig_dow.update_layout(
        height=400,
        margin=dict(l=20, r=20, t=20, b=20),
        xaxis=dict(tickmode="linear", tick0=0, dtick=2, title="Hour of Day (0–23)"),
        yaxis_title="Average Hourly Energy (kWh)",
        legend=dict(orientation="h", yanchor="bottom", y=1.02, xanchor="right", x=1)
    )
    st.plotly_chart(fig_dow, use_container_width=True)

# ==============================================================================
# TAB 3: MACHINE LEARNING FORECASTING
# ==============================================================================
elif nav_choice == "🤖 Machine Learning Forecasting":
    st.markdown('<div class="main-title">🤖 Machine Learning Forecasting (Spark MLlib)</div>', unsafe_allow_html=True)
    st.markdown('<div class="sub-title">Next-day household electricity consumption prediction on an untouched chronological test set (213 days, 2010)</div>', unsafe_allow_html=True)

    # Model Evaluation Metrics Cards
    val_m = metrics_dict["validation_metrics"]
    test_m = metrics_dict["test_metrics"]
    best_m = metrics_dict["selected_best_model"]

    col1, col2, col3, col4 = st.columns(4)
    with col1:
        st.metric("Best Model", best_m["model_name"].replace("_", " "), delta="Selected via Val RMSE")
    with col2:
        st.metric("Test RMSE", f"{best_m['test_rmse']:.4f} kWh", delta="-19.5% vs Baseline")
    with col3:
        st.metric("Test MAE", f"{best_m['test_mae']:.4f} kWh", delta="-14.9% vs Baseline")
    with col4:
        st.metric("Test R² Score", f"{best_m['test_r2']:.4f}", delta="+0.2812 vs Baseline")

    st.markdown("---")

    # Time-Series Actual vs Predicted Chart
    st.markdown("#### **Test Period Actual vs. Model Predictions (April 2010 – November 2010)**")
    show_rf = st.checkbox("Show Random Forest Regressor (Spark MLlib)", value=True)
    show_lr = st.checkbox("Show Linear Regression (Spark MLlib)", value=True)
    show_base = st.checkbox("Show Naive Baseline (Lag-1 Persistence)", value=True)

    fig_preds = go.Figure()
    fig_preds.add_trace(go.Scatter(
        x=preds_df["Date"],
        y=preds_df["Actual_kWh"],
        mode="lines",
        name="Actual Consumption (kWh)",
        line=dict(color="#0f172a", width=2.5)
    ))

    if show_rf:
        fig_preds.add_trace(go.Scatter(
            x=preds_df["Date"],
            y=preds_df["RandomForest_Pred_kWh"],
            mode="lines",
            name="Random Forest MLlib Pred",
            line=dict(color="#16a34a", width=2.0)
        ))

    if show_lr:
        fig_preds.add_trace(go.Scatter(
            x=preds_df["Date"],
            y=preds_df["LinearRegression_Pred_kWh"],
            mode="lines",
            name="Linear Regression Pred",
            line=dict(color="#2563eb", width=1.5, dash="dash")
        ))

    if show_base:
        fig_preds.add_trace(go.Scatter(
            x=preds_df["Date"],
            y=preds_df["Baseline_Pred_kWh"],
            mode="lines",
            name="Naive Baseline (Lag-1)",
            line=dict(color="#f97316", width=1.0, dash="dot"),
            opacity=0.7
        ))

    fig_preds.update_layout(
        height=420,
        margin=dict(l=20, r=20, t=20, b=20),
        xaxis_title="Test Date (2010)",
        yaxis_title="Energy Consumption (kWh)",
        legend=dict(orientation="h", yanchor="bottom", y=1.02, xanchor="right", x=1),
        hovermode="x unified"
    )
    st.plotly_chart(fig_preds, use_container_width=True)

    # Comparative Metrics Table & Bar Chart
    col_table, col_bar = st.columns([1, 1])

    with col_table:
        st.markdown("#### **Comparative Model Evaluation Metrics**")
        models_summary = pd.DataFrame([
            {
                "Model": "Naive Persistence Baseline",
                "Val RMSE": val_m["Naive_Baseline"]["RMSE"],
                "Test MAE": test_m["Naive_Baseline"]["MAE"],
                "Test RMSE": test_m["Naive_Baseline"]["RMSE"],
                "Test R²": test_m["Naive_Baseline"]["R2"],
                "Test MAPE": f"{test_m['Naive_Baseline'].get('MAPE_pct', 19.2)}%"
            },
            {
                "Model": "Spark MLlib Linear Regression",
                "Val RMSE": val_m["Linear_Regression"]["RMSE"],
                "Test MAE": test_m["Linear_Regression"]["MAE"],
                "Test RMSE": test_m["Linear_Regression"]["RMSE"],
                "Test R²": test_m["Linear_Regression"]["R2"],
                "Test MAPE": f"{test_m['Linear_Regression'].get('MAPE_pct', 18.21)}%"
            },
            {
                "Model": "Spark MLlib Random Forest Regressor",
                "Val RMSE": val_m["Random_Forest"]["RMSE"],
                "Test MAE": test_m["Random_Forest"]["MAE"],
                "Test RMSE": test_m["Random_Forest"]["RMSE"],
                "Test R²": test_m["Random_Forest"]["R2"],
                "Test MAPE": f"{test_m['Random_Forest'].get('MAPE_pct', 18.13)}%"
            }
        ])
        st.dataframe(models_summary, hide_index=True, use_container_width=True)
        st.caption("Training Configuration: 70% Train (989 days), 15% Validation (211 days), 15% Test (213 days). Strict chronological split with zero forward leakage.")

    with col_bar:
        st.markdown("#### **Error Metrics Comparison (MAE vs RMSE)**")
        fig_bar = go.Figure(data=[
            go.Bar(name="MAE (kWh)", x=models_summary["Model"], y=models_summary["Test MAE"], marker_color="#60a5fa"),
            go.Bar(name="RMSE (kWh)", x=models_summary["Model"], y=models_summary["Test RMSE"], marker_color="#f87171"),
            go.Bar(name="R² Score", x=models_summary["Model"], y=models_summary["Test R²"], marker_color="#4ade80")
        ])
        fig_bar.update_layout(
            barmode="group",
            height=320,
            margin=dict(l=20, r=20, t=20, b=20),
            legend=dict(orientation="h", yanchor="bottom", y=1.02, xanchor="right", x=1)
        )
        st.plotly_chart(fig_bar, use_container_width=True)

# ==============================================================================
# TAB 4: SUSTAINABILITY & SDG 7 INSIGHTS
# ==============================================================================
elif nav_choice == "🌿 Sustainability & SDG 7 Insights":
    st.markdown('<div class="main-title">🌿 Sustainability & UN SDG 7 Insights</div>', unsafe_allow_html=True)
    st.markdown('<div class="sub-title">Data-driven peak shaving, demand-side management, and statistical energy waste identification</div>', unsafe_allow_html=True)

    _hour_kw = hourly_df.groupby("Hour")["Avg_power_kW"].mean()
    _hour_kwh = hourly_df.groupby("Hour")["Energy_kWh"].sum()
    col1, col2, col3, col4 = st.columns(4)
    with col1:
        st.metric("Peak Stress Hours", "18:00 – 21:00", delta=f"Average {_hour_kw.loc[18:21].mean():.2f} kW")
    with col2:
        st.metric("Off-Peak Valley", "01:00 – 05:00", delta=f"Average {_hour_kw.loc[1:5].mean():.2f} kW")
    with col3:
        st.metric("Peak-to-Trough Ratio", f"{_hour_kw.max() / _hour_kw.min():.1f}x", delta="Busiest hour vs quietest hour")
    with col4:
        st.metric("Energy Used 18:00 – 23:59", f"{_hour_kwh.loc[18:23].sum() / _hour_kwh.sum() * 100:.1f}%", delta="Largest time-of-day band")

    st.markdown("---")

    col_anom, col_shave = st.columns([1, 1])

    with col_anom:
        st.markdown("#### **Statistical Anomaly Detection (Waste Identification)**")
        std_multiplier = st.slider("Anomaly Sensitivity (Standard Deviations above Mean)", 1.5, 3.0, 2.0, 0.1)
        mean_e = filtered_daily["Energy_kWh"].mean()
        std_e = filtered_daily["Energy_kWh"].std()
        threshold = mean_e + std_multiplier * std_e
        
        filtered_daily["Is_Anomaly"] = filtered_daily["Energy_kWh"] > threshold
        anomaly_count = filtered_daily["Is_Anomaly"].sum()

        fig_anom = px.scatter(
            filtered_daily,
            x="Date",
            y="Energy_kWh",
            color="Is_Anomaly",
            color_discrete_map={False: "#60a5fa", True: "#dc2626"},
            labels={"Is_Anomaly": "Anomaly Flag"}
        )
        fig_anom.add_hline(
            y=threshold,
            line_dash="dash",
            line_color="#dc2626",
            annotation_text=f"Threshold: {threshold:.1f} kWh ({std_multiplier}σ)"
        )
        fig_anom.update_layout(height=380, margin=dict(l=20, r=20, t=20, b=20), yaxis_title="Daily Energy (kWh)")
        st.plotly_chart(fig_anom, use_container_width=True)
        st.warning(f"⚠️ **{anomaly_count} anomaly days detected** exceeding {threshold:.1f} kWh. These signify excessive heating/cooling, device malfunction, or insulation loss.")

    with col_shave:
        st.markdown("#### **Peak Shaving & Load Shifting Opportunity Windows**")
        hourly_demand = hourly_df.groupby("Hour")["Avg_power_kW"].mean().reset_index()
        
        # Color code by tariff category
        hourly_demand["Tariff_Tier"] = "Mid-Peak"
        hourly_demand.loc[hourly_demand["Hour"].isin([1, 2, 3, 4, 5]), "Tariff_Tier"] = "Off-Peak (Low Cost)"
        hourly_demand.loc[hourly_demand["Hour"].isin([18, 19, 20, 21]), "Tariff_Tier"] = "On-Peak (Grid Stress)"

        fig_tier = px.bar(
            hourly_demand,
            x="Hour",
            y="Avg_power_kW",
            color="Tariff_Tier",
            color_discrete_map={
                "Off-Peak (Low Cost)": "#22c55e",
                "Mid-Peak": "#3b82f6",
                "On-Peak (Grid Stress)": "#ef4444"
            },
            title="Hourly Power Demand by Tariff Window (kW)"
        )
        fig_tier.update_layout(
            height=380,
            margin=dict(l=20, r=20, t=40, b=20),
            xaxis=dict(tickmode="linear", tick0=0, dtick=2),
            yaxis_title="Average Power Demand (kW)",
            legend=dict(orientation="h", yanchor="bottom", y=1.02, xanchor="right", x=1)
        )
        st.plotly_chart(fig_tier, use_container_width=True)

    st.markdown("---")
    st.markdown("#### **Practical Energy Conservation Recommendations Aligned with UN SDG 7**")
    rec1, rec2, rec3 = st.columns(3)
    with rec1:
        st.markdown("##### 🔌 **1. Nocturnal Appliance Scheduling**")
        st.write("Shift major washing machine, tumble dryer, and dishwasher cycles to the **01:00 – 05:00** nocturnal window using delayed-start timers, avoiding peak residential grid congestion.")
    with rec2:
        st.markdown("##### 🌡️ **2. Smart Thermostat Modulation**")
        st.write("Sub-meter 3 (water heater and climate control) represents **35.5%** of total load. Pre-heating or pre-cooling water and living spaces during off-peak hours cuts peak thermal demand by up to 25%.")
    with rec3:
        st.markdown("##### 💡 **3. Phantom Load Mitigation**")
        st.write("About **51.2%** of energy resides in the unmetered remainder (lighting and entertainment standbys). Deploying smart power strips can reduce continuous parasitic base-load by 10–15%.")

# ==============================================================================
# TAB: HADOOP & HIVE CLUSTER RESULTS
# ==============================================================================
elif nav_choice == "🐘 Hadoop & Hive Cluster Results":
    st.markdown('<div class="main-title">🐘 Hadoop & Hive Cluster Results</div>', unsafe_allow_html=True)
    st.markdown('<div class="sub-title">Outputs of the jobs that ran on the single-node Hadoop cluster: MapReduce on YARN and Apache Hive</div>', unsafe_allow_html=True)

    hourly_mr_path = os.path.join("hadoop", "mapreduce_yarn_hourly_output.txt")
    daily_mr_path = os.path.join("hadoop", "mapreduce_yarn_daily_output.txt")

    st.markdown("### MapReduce job 1: daily energy totals")
    if os.path.exists(daily_mr_path):
        mr_daily = pd.read_csv(daily_mr_path, sep="\t", header=None, names=["Date", "Energy_kWh", "Readings"])
        mr_daily["Date_ISO"] = pd.to_datetime(mr_daily["Date"], format="%d/%m/%Y").dt.strftime("%Y-%m-%d")
        merged = mr_daily.merge(daily_df[["Date_ISO", "Energy_kWh"]], on="Date_ISO", suffixes=("_mr", "_pipeline"))
        diff = (merged["Energy_kWh_mr"] - merged["Energy_kWh_pipeline"]).abs()
        c1, c2, c3, c4 = st.columns(4)
        c1.metric("Days produced by the reducer", f"{len(mr_daily):,}")
        c2.metric("Readings aggregated", f"{int(mr_daily['Readings'].sum()):,}")
        c3.metric("Days matching the pipeline table", f"{len(merged):,}")
        c4.metric("Largest difference", f"{diff.max():.4f} kWh")
    else:
        st.info("Run `bash run_on_mac.sh` to produce the MapReduce output.")

    st.markdown("### MapReduce job 2: hour-of-day load profile")
    if os.path.exists(hourly_mr_path):
        mr_hourly = pd.read_csv(hourly_mr_path, sep="\t", header=None,
                                names=["Hour", "Total_kWh", "Readings", "Avg_Power_kW", "Peak_Power_kW"]).sort_values("Hour")
        fig_h = go.Figure()
        fig_h.add_trace(go.Bar(x=mr_hourly["Hour"], y=mr_hourly["Avg_Power_kW"], name="Average power (kW)", marker_color="#0f766e"))
        fig_h.add_trace(go.Scatter(x=mr_hourly["Hour"], y=mr_hourly["Peak_Power_kW"], name="Peak power (kW)",
                                   mode="lines+markers", line=dict(color="#f97316", width=2), yaxis="y2"))
        fig_h.update_layout(
            height=380, margin=dict(l=20, r=20, t=30, b=20),
            xaxis=dict(title="Hour of day", dtick=1),
            yaxis=dict(title="Average power (kW)"),
            yaxis2=dict(title="Peak power (kW)", overlaying="y", side="right", showgrid=False),
            legend=dict(orientation="h", yanchor="bottom", y=1.02, xanchor="right", x=1),
        )
        st.plotly_chart(fig_h, use_container_width=True)
        top = mr_hourly.sort_values("Avg_Power_kW", ascending=False).iloc[0]
        low = mr_hourly.sort_values("Avg_Power_kW").iloc[0]
        st.caption(f"Highest average demand at {int(top['Hour']):02d}:00 ({top['Avg_Power_kW']:.2f} kW); "
                   f"lowest at {int(low['Hour']):02d}:00 ({low['Avg_Power_kW']:.2f} kW). "
                   f"Computed by Hadoop Streaming over {int(mr_hourly['Readings'].sum()):,} readings.")
    else:
        st.info("Run `bash run_on_mac.sh` to produce the hour-of-day MapReduce output.")

    st.markdown("### Apache Hive query results")
    hive_dir = os.path.join("hive", "cluster_results")
    hive_report = os.path.join("hive", "hive_cluster_report.md")
    hive_files = sorted(f for f in os.listdir(hive_dir) if f.endswith(".csv")) if os.path.isdir(hive_dir) else []
    if hive_files:
        titles = {}
        if os.path.exists(hive_report):
            with open(hive_report, "r", encoding="utf-8") as fh:
                for line in fh:
                    if line.startswith("## Query "):
                        num, _, title = line[len("## Query "):].strip().partition(": ")
                        titles[f"q{int(num):02d}.csv"] = f"Q{num}: {title}"
        choice = st.selectbox("Query executed on HiveServer2 (MapReduce engine on YARN)", hive_files,
                              format_func=lambda f: titles.get(f, f))
        res = pd.read_csv(os.path.join(hive_dir, choice))
        st.dataframe(res, use_container_width=True, hide_index=True, height=min(420, 60 + 35 * len(res)))
        st.caption(f"{len(res):,} rows returned by Hive. Source file: `hive/cluster_results/{choice}`")
    else:
        st.info("Run `bash run_on_mac.sh` to execute the HiveQL queries on the Hive server.")

# ==============================================================================
# TAB 5: ACADEMIC & ARCHITECTURE PORTFOLIO
# ==============================================================================
elif nav_choice == "📚 Project & Big Data Architecture":
    st.markdown('<div class="main-title">📚 Project Details & Big Data Architecture</div>', unsafe_allow_html=True)
    st.markdown('<div class="sub-title">Batch 30 Big Data course project: what runs where, and how the pieces connect</div>', unsafe_allow_html=True)

    col1, col2 = st.columns([1, 1])

    with col1:
        st.markdown("### **Academic Project Details**")
        st.markdown("""
        - **Project Title:** Smart Energy Consumption Analytics & Forecasting
        - **Academic Subject:** Big Data Analytics (BDA)
        - **Batch Number:** **Batch 30**
        - **Team Members:**
          - **Vaibhav** — Roll No: `AP23110010425`
          - **Saubhagya Kashyap** — Roll No: `AP23110010439`
        - **Target SDG:** **UN SDG 7 — Affordable and Clean Energy (Level 3)**
        - **Source code:** [`vaibhavv-x/Smart-Energy-Analytics-`](https://github.com/vaibhavv-x/Smart-Energy-Analytics-)
        """)

        st.markdown("### **What Runs Where**")
        st.markdown("""
        | Component | Technology | How it runs |
        |---|---|---|
        | **Storage** | Hadoop HDFS | Single-node cluster; raw file, cleaned tables, features and Hive warehouse under `/smart-energy` |
        | **Batch jobs** | Hadoop MapReduce on YARN | Two Hadoop Streaming jobs over 2.07 million rows: daily totals and hour-of-day load profile |
        | **Data warehouse** | Apache Hive (HiveServer2) | ORC and Parquet tables; 12 HiveQL queries executed as MapReduce jobs on YARN |
        | **Feature engineering** | PySpark window functions | Reads the cleaned table from HDFS; 15 leak-free features |
        | **Machine learning** | Spark MLlib | Linear Regression and Random Forest against a naive baseline |
        | **Visualization** | Streamlit, Plotly, Matplotlib | This dashboard and four report figures |
        | **Testing** | pytest | 35 automated tests |
        """)

    with col2:
        st.markdown("### **End-to-End Architecture**")
        st.code("""
UCI raw file (2,075,259 one-minute readings)
       │
       ▼
HDFS  /smart-energy/raw
       │
       ├──────────────────────────────┬─────────────────────────┐
       ▼                              ▼                         ▼
MapReduce on YARN              Cleaning (pandas)          Hive external table
 - daily totals                daily + hourly tables       over the raw file
 - hour-of-day profile                │
                                      ▼
                         HDFS  /smart-energy/cleaned
                                      │
                 ┌────────────────────┴───────────────────┐
                 ▼                                        ▼
   Hive warehouse (ORC / Parquet)            PySpark feature pipeline
   12 HiveQL queries on YARN                 HDFS /smart-energy/features
                                                          │
                                                          ▼
                                         Spark MLlib (baseline, LR, RF)
                                                          │
                                                          ▼
                                     Streamlit dashboard and report figures
        """, language="text")

# ==============================================================================
# FOOTER
# ==============================================================================
st.markdown("---")
st.markdown(
    "<div style='text-align: center; color: #64748b; font-size: 0.85rem;'>"
    "Smart Energy Consumption Analytics & Forecasting | Batch 30 | Big Data Analytics<br/>"
    "Developed by Vaibhav & Saubhagya Kashyap | Aligned with UN Sustainable Development Goal 7"
    "</div>",
    unsafe_allow_html=True
)
