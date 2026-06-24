/*
======================================================================
PROJECT: Northwind Business Analysis
FILE: 02_sales_analysis.sql
DESCRIPTION: Macroeconomic Revenue Trends, Seasonality Analysis, 
             and Customer Acquisition Growth.
METHODOLOGY STEP: [A] Exploratory Analysis (Sales Performance)
======================================================================
*/

-- ===================================================================
-- SECTION 1: MACRO REVENUE TRENDS & SEASONALITY
-- ===================================================================

-- -------------------------------------------------------------------
-- 1.1. Monthly and Yearly Revenue Breakdown
-- Objective: Identify high-level historical net revenue trends 
--            and track periodic sales patterns.
-- -------------------------------------------------------------------
SELECT 
    YEAR(so.OrderDate) AS [Year], 
    MONTH(so.OrderDate) AS [Month], 
    SUM(od.Quantity * (od.UnitPrice * (1 - od.Discount))) AS NetRevenueOfTheMonth
FROM dbo.Orders so 
INNER JOIN dbo.[Order Details] od ON so.OrderID = od.OrderID 
GROUP BY YEAR(so.OrderDate), MONTH(so.OrderDate)
ORDER BY [Year], [Month];


-- -------------------------------------------------------------------
-- 1.2. Trajectory Analysis via Cumulative Revenue
-- Objective: Use window functions to track the continuous speed of 
--            revenue generation across months and years.
-- -------------------------------------------------------------------
SELECT 
    YEAR(o.OrderDate) AS [OrderYear],
    MONTH(o.OrderDate) AS [OrderMonth],
    SUM(od.Quantity * od.UnitPrice * (1 - CAST(od.Discount AS DECIMAL(10,4)))) AS [Monthly_Revenue],
    SUM(
        SUM(od.Quantity * od.UnitPrice * (1 - CAST(od.Discount AS DECIMAL(10,4))))
    ) OVER (
        ORDER BY YEAR(o.OrderDate), MONTH(o.OrderDate)
    ) AS [Cumulative_Revenue]
FROM dbo.[Order Details] AS od
INNER JOIN dbo.Orders AS o ON od.OrderID = o.OrderID
GROUP BY 
    YEAR(o.OrderDate),
    MONTH(o.OrderDate)
ORDER BY 
    [OrderYear],
    [OrderMonth];


-- ===================================================================
-- SECTION 2: CUSTOMER ACQUISITION DYNAMICS
-- ===================================================================

-- -------------------------------------------------------------------
-- 2.1. New Customer Cohort Breakdown by Year
-- Objective: Count how many brand new accounts placed their very 
--            first order each year to evaluate market growth.
-- -------------------------------------------------------------------
WITH FirstOrders AS (
    SELECT
        CustomerID,
        MIN(OrderDate) AS FirstOrderDate
    FROM dbo.Orders
    GROUP BY CustomerID
)
SELECT
    YEAR(FirstOrderDate) AS ClientAcquisitionYear,
    COUNT(*) AS NumOfNewClients
FROM FirstOrders
GROUP BY YEAR(FirstOrderDate)
ORDER BY ClientAcquisitionYear;