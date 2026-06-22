# Northwind SQL Business Analysis

## Project Overview

This project explores the Northwind database using SQL Server to analyze sales performance, customer activity, product performance, and operational business KPIs.

The goal is to simulate a real-world business analysis workflow by transforming raw transactional data into actionable insights using SQL.

Through this project, business-oriented questions are explored to better understand commercial performance, customer behavior, product trends, and sales distribution.

---

## 🎯 Methodological Framework: CQNARD

To ensure a rigorous, business-driven approach and compelling data storytelling, this project is structured around the **CQNARD** framework:
* **C**ontext (Business Context & Environment)
* **Q**uestion (Core Business Questions & KPIs)
* **N**etcleaning (Data Cleansing & Preparation)
* **A**nalysis (Exploratory Data Querying)
* **R**esults (Key Insights & Findings)
* **D**ecision (Actionable Recommendations & Dashboarding)

---

## Database Description

The Northwind database is a sample database originally created by Microsoft and based on a fictional company called **Northwind Traders**, which imports and exports specialty food products worldwide.

The database contains operational and sales-related information, including:
* Customers
* Orders & Order Details
* Products and categories
* Employees
* Suppliers
* Shipping information

---

## 1. [C] Business Context
As a Data Analyst at Northwind Traders, the primary objective is to identify revenue growth drivers, map logistical efficiencies, and decode customer purchasing behavior to guide the executive team's strategic commercial decisions.

---

## 2. [Q] Business Questions & Target KPIs

To structure the data exploration phase, the analysis aims to answer specific decision-making business questions:

| Business Dimension | Core Business Question | Associated KPIs |
| :--- | :--- | :--- |
| **Sales Performance** | What is the macro trend of net revenue? Is there a distinct seasonality pattern? | Monthly/Annual Revenue, MoM Growth, Average Order Value (AOV) |
| **Product & Category** | Which products generate 80% of total revenue (Pareto Principle)? Which products are obsolete? | Revenue per Product/Category, Sales Volume, Turnover Rate |
| **Customer Activity** | Who are our "Champion" customers, and which accounts show a high risk of churning? | Customer Lifetime Revenue, Purchase Frequency, Recency |
| **Operations & Logistics** | Which shippers perform best regarding lead times? Which countries face the highest delay rates? | Average Shipping Lead Time, Delay Rate per Destination Country |

---

## 3. [N] Data Cleaning & Preparation

Before running heavy aggregations, a critical data preprocessing and validation phase was established:
* **Net Revenue Formula:** To avoid revenue overestimation, discounts must be programmatically factored in at the line-item level:  
  $$\text{Net Revenue} = \text{UnitPrice} \times \text{Quantity} \times (1 - \text{Discount})$$
* **Handling Missing Values:** Analyzing orders without a shipping date (`ShippedDate IS NULL`) to separate pending active shipments from potential logistical anomalies.
* **Integrity Constraints:** Checking for data type coherence and temporal anomalies (e.g., ensuring `ShippedDate` or `RequiredDate` is never prior to `OrderDate`).

---

## 4. [A] Exploratory Analysis & Repository Structure

SQL scripts are engineered modularly to align with each key step of the business analysis workflow:

```text
northwind-sql-analysis/
│
├── sql/
│   ├── 01_data_cleaning.sql          # [N] Cleansing, NULL handling, and data type formatting
│   ├── 02_sales_analysis.sql         # [A] Macro revenue trends, seasonality, and AOV
│   ├── 03_customer_analysis.sql      # [A] Customer segmentation and revenue concentration
│   ├── 04_product_analysis.sql       # [A] Top/Flop products and category performance
│   ├── 05_employee_analysis.sql      # [A] Sales force performance assessment
│   └── 06_kpi_views.sql              # [D] Database views generated for Looker Studio ingestion
│
├── insights/                         # [R] Documented reports, findings, and text summaries
├── screenshots/                      # [D] Visual captures of the interactive dashboard
└── README.md
