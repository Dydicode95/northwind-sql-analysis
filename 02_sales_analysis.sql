/*
======================================================================
PROJECT: Northwind Business Analysis
FILE: 02_sales_analysis.sql
DESCRIPTION: Macroeconomic Revenue Trends, Cumulative Growth,
             and Customer Acquisition Dynamics.
METHODOLOGY STEP: [A] Exploratory Analysis (Sales Performance)
======================================================================
*/

-- ===================================================================
-- SECTION 1: MACRO REVENUE TRENDS & GROWTH VELOCITY
-- ===================================================================

SELECT 
    [OrderYear], 
    [OrderMonth], 
    ROUND(Monthly_Revenue, 2) AS [Monthly_Revenue],
    ROUND(SUM(Monthly_Revenue) OVER (ORDER BY [OrderYear], [OrderMonth]), 2) AS [Cumulative_Revenue],
    ROUND(((Monthly_Revenue - LAG(Monthly_Revenue, 1) OVER (ORDER BY [OrderYear], [OrderMonth])) / NULLIF(LAG(Monthly_Revenue, 1) OVER (ORDER BY [OrderYear], [OrderMonth]), 0)) * 100, 2) AS [MoM_Growth_Percentage]
FROM ( 
    SELECT 
        YEAR(o.OrderDate) AS [OrderYear],
        MONTH(o.OrderDate) AS [OrderMonth],
        SUM(od.Quantity * od.UnitPrice * (1 - CAST(od.Discount AS DECIMAL(10,4)))) AS Monthly_Revenue
    FROM dbo.[Order Details] AS od
    INNER JOIN dbo.Orders AS o ON od.OrderID = o.OrderID
    GROUP BY YEAR(o.OrderDate), MONTH(o.OrderDate)
) AS BaseData
ORDER BY [OrderYear], [OrderMonth];

-- ===================================================================
-- SECTION 2: CUSTOMER ACQUISITION DYNAMICS
-- ===================================================================

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