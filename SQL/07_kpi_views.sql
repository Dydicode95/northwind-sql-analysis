USE master;
GO

-- =========================================================================================
-- FILE: 07_kpi_views.sql
-- DIALECT: SQL Server / T-SQL
-- PURPOSE: Generate the final Business Intelligence Data Marts for Looker Studio ingestion.
-- AUTHOR: Data Analyst (Northwind Project)
--
-- Compatibility note:
-- This script avoids CREATE OR ALTER VIEW so it remains compatible with older SQL Server
-- versions. Each view is created as a placeholder only if it does not already exist,
-- then ALTER VIEW applies the final definition.
-- =========================================================================================


-- =========================================================================================
-- VIEW 1: REGIONAL TURNOVER & MACRO SALES
-- Business Objective:
-- Analyze regional order volume, gross revenue, net revenue, and discount impact.
-- Grain: one row = one shipping country.
-- =========================================================================================

IF OBJECT_ID(N'dbo.v_bi_regional_turnover_update', N'V') IS NULL
    EXEC(N'CREATE VIEW dbo.v_bi_regional_turnover_update AS SELECT 1 AS Placeholder;');
GO

ALTER VIEW dbo.v_bi_regional_turnover_update AS

SELECT
    o.ShipCountry,

    COUNT(DISTINCT o.OrderID) AS NumberOfOrders,

    SUM(
        CAST(od.Quantity AS DECIMAL(18,4))
        * CAST(od.UnitPrice AS DECIMAL(18,4))
    ) AS GrossTurnover,

    SUM(
        CAST(od.Quantity AS DECIMAL(18,4))
        * CAST(od.UnitPrice AS DECIMAL(18,4))
        * (1 - CAST(od.Discount AS DECIMAL(18,4)))
    ) AS NetTurnover,

    SUM(
        CAST(od.Quantity AS DECIMAL(18,4))
        * CAST(od.UnitPrice AS DECIMAL(18,4))
        * CAST(od.Discount AS DECIMAL(18,4))
    ) AS TotalDiscountAmount

FROM dbo.Orders o

INNER JOIN dbo.[Order Details] od
    ON o.OrderID = od.OrderID

GROUP BY
    o.ShipCountry;
GO


-- =========================================================================================
-- VIEW 2: ORDER VALUE OUTLIER DETECTION
-- Business Objective:
-- Identify unusually low- and high-value orders using the IQR methodology.
-- Quartile thresholds are calculated across all Northwind orders.
-- Grain: one row = one order.
-- =========================================================================================

IF OBJECT_ID(N'dbo.v_bi_order_value_outliers', N'V') IS NULL
    EXEC(N'CREATE VIEW dbo.v_bi_order_value_outliers AS SELECT 1 AS Placeholder;');
GO

ALTER VIEW dbo.v_bi_order_value_outliers AS

WITH OrderAmounts AS (
    SELECT
        o.ShipCountry,
        od.OrderID,

        SUM(
            CAST(od.Quantity AS DECIMAL(18,4))
            * CAST(od.UnitPrice AS DECIMAL(18,4))
            * (1 - CAST(od.Discount AS DECIMAL(18,4)))
        ) AS OrderAmount

    FROM dbo.[Order Details] od

    INNER JOIN dbo.Orders o
        ON od.OrderID = o.OrderID

    GROUP BY
        o.ShipCountry,
        od.OrderID
),

Quartiles AS (
    SELECT
        ShipCountry,
        OrderID,
        OrderAmount,

        PERCENTILE_CONT(0.25)
            WITHIN GROUP (ORDER BY OrderAmount)
            OVER () AS Q1,

        PERCENTILE_CONT(0.75)
            WITHIN GROUP (ORDER BY OrderAmount)
            OVER () AS Q3

    FROM OrderAmounts
),

Classification AS (
    SELECT
        ShipCountry,
        OrderID,
        OrderAmount,
        Q1,
        Q3,
        Q3 - Q1 AS IQR

    FROM Quartiles
)

SELECT
    ShipCountry,
    OrderID,
    OrderAmount,

    CASE
        WHEN OrderAmount < (Q1 - 1.5 * IQR)
            THEN 'Low-Value Outlier'
        WHEN OrderAmount > (Q3 + 1.5 * IQR)
            THEN 'High-Value Outlier'
        ELSE 'Typical Range'
    END AS OrderValueClass

FROM Classification;
GO


-- =========================================================================================
-- VIEW 3: PRODUCT PERFORMANCE BY REGION & MONTH
-- Business Objective:
-- Track monthly product revenue and sales volume by country,
-- and rank products within each country-month.
-- Grain: one row = one product x shipping country x month.
--
-- BI note:
-- The BI source retains all available months. Trend visuals should exclude an incomplete
-- final month when making month-over-month comparisons.
-- =========================================================================================

IF OBJECT_ID(N'dbo.v_bi_product_performance_by_region', N'V') IS NULL
    EXEC(N'CREATE VIEW dbo.v_bi_product_performance_by_region AS SELECT 1 AS Placeholder;');
GO

ALTER VIEW dbo.v_bi_product_performance_by_region AS

WITH MonthlyProductPerformance AS (

    SELECT
        o.ShipCountry,

        DATEFROMPARTS(
            YEAR(o.OrderDate),
            MONTH(o.OrderDate),
            1
        ) AS OrderMonth,

        p.ProductID,
        p.ProductName,
        c.CategoryName,

        SUM(CAST(od.Quantity AS BIGINT)) AS TotalQuantitySold,

        SUM(
            CAST(od.Quantity AS DECIMAL(18,4))
            * CAST(od.UnitPrice AS DECIMAL(18,4))
            * (1 - CAST(od.Discount AS DECIMAL(18,4)))
        ) AS NetRevenue

    FROM dbo.[Order Details] od

    INNER JOIN dbo.Orders o
        ON od.OrderID = o.OrderID

    INNER JOIN dbo.Products p
        ON od.ProductID = p.ProductID

    INNER JOIN dbo.Categories c
        ON p.CategoryID = c.CategoryID

    GROUP BY
        o.ShipCountry,
        DATEFROMPARTS(
            YEAR(o.OrderDate),
            MONTH(o.OrderDate),
            1
        ),
        p.ProductID,
        p.ProductName,
        c.CategoryName
)

SELECT
    ShipCountry,
    OrderMonth,
    ProductID,
    ProductName,
    CategoryName,
    TotalQuantitySold,
    NetRevenue,

    RANK() OVER (
        PARTITION BY ShipCountry, OrderMonth
        ORDER BY NetRevenue DESC
    ) AS RegionalMonthlyRevenueRank

FROM MonthlyProductPerformance;
GO


-- =========================================================================================
-- VIEW 4: SHIPPING & LOGISTICS PERFORMANCE
-- Business Objective:
-- Track order-to-shipment lead times, identify shipments made after the required date,
-- and analyze freight amounts by carrier, country, and over time.
-- Grain: one row = one valid shipped order.
--
-- Analytical note:
-- ShippedDate represents the shipment date, not the customer delivery date.
-- Therefore, this view measures order-to-shipment lead time and shipment timing,
-- not actual delivery performance.
-- =========================================================================================

IF OBJECT_ID(N'dbo.v_bi_shipping_performance', N'V') IS NULL
    EXEC(N'CREATE VIEW dbo.v_bi_shipping_performance AS SELECT 1 AS Placeholder;');
GO

ALTER VIEW dbo.v_bi_shipping_performance AS

SELECT
    o.OrderID,
    o.ShipCountry,
    s.CompanyName AS ShipperName,

    o.OrderDate,
    o.RequiredDate,
    o.ShippedDate,

    DATEFROMPARTS(
        YEAR(o.OrderDate),
        MONTH(o.OrderDate),
        1
    ) AS OrderMonth,

    DATEDIFF(
        DAY,
        o.OrderDate,
        o.ShippedDate
    ) AS OrderToShipmentLeadTimeDays,

    CASE
        WHEN o.RequiredDate IS NULL
            THEN 'Required Date Missing'
        WHEN o.ShippedDate > o.RequiredDate
            THEN 'Shipped After Required Date'
        ELSE 'Shipped By Required Date'
    END AS ShipmentTimingStatus,

    CASE
        WHEN o.RequiredDate IS NULL
            THEN NULL
        WHEN o.ShippedDate > o.RequiredDate
            THEN 1
        ELSE 0
    END AS IsShippedAfterRequiredDate,

    o.Freight AS FreightAmount

FROM dbo.Orders o

INNER JOIN dbo.Shippers s
    ON o.ShipVia = s.ShipperID

WHERE o.ShippedDate IS NOT NULL
  AND o.ShippedDate >= o.OrderDate;
GO


-- =========================================================================================
-- VIEW 5: CUSTOMER RFM SEGMENTATION
-- Business Objective:
-- Segment customers with purchase history based on Recency, Frequency and Monetary value,
-- and identify high-value customers as well as customers showing signs of inactivity.
-- Grain: one row = one customer with purchase history.
--
-- Analytical note:
-- Recency is measured relative to the latest order date available in the dataset.
-- This is an inactivity indicator, not an observed churn variable.
-- =========================================================================================

IF OBJECT_ID(N'dbo.v_bi_customer_360', N'V') IS NULL
    EXEC(N'CREATE VIEW dbo.v_bi_customer_360 AS SELECT 1 AS Placeholder;');
GO

ALTER VIEW dbo.v_bi_customer_360 AS

WITH ReferenceDate AS (
    SELECT
        MAX(OrderDate) AS AnalysisDate

    FROM dbo.Orders
),

OrderCosts AS (
    SELECT
        OrderID,

        SUM(
            CAST(Quantity AS DECIMAL(18,4))
            * CAST(UnitPrice AS DECIMAL(18,4))
            * (1 - CAST(Discount AS DECIMAL(18,4)))
        ) AS NetOrderAmount

    FROM dbo.[Order Details]

    GROUP BY
        OrderID
),

CustomerMetrics AS (
    SELECT
        o.CustomerID,
        MAX(o.OrderDate) AS LastOrderDate,
        COUNT(DISTINCT o.OrderID) AS Frequency,
        SUM(oc.NetOrderAmount) AS MonetaryValue

    FROM dbo.Orders o

    INNER JOIN OrderCosts oc
        ON o.OrderID = oc.OrderID

    GROUP BY
        o.CustomerID
),

RecencyCalculated AS (
    SELECT
        cm.CustomerID,
        rd.AnalysisDate,
        cm.LastOrderDate,
        cm.Frequency,
        cm.MonetaryValue,

        DATEDIFF(
            DAY,
            cm.LastOrderDate,
            rd.AnalysisDate
        ) AS RecencyDays

    FROM CustomerMetrics cm

    CROSS JOIN ReferenceDate rd
),

RFM_Percentiles AS (
    SELECT
        *,

        PERCENT_RANK() OVER (
            ORDER BY RecencyDays DESC
        ) AS R_Percentile,

        PERCENT_RANK() OVER (
            ORDER BY Frequency ASC
        ) AS F_Percentile,

        PERCENT_RANK() OVER (
            ORDER BY MonetaryValue ASC
        ) AS M_Percentile

    FROM RecencyCalculated
),

RFM_Scores AS (
    SELECT
        *,

        CASE
            WHEN R_Percentile < 0.25 THEN 1
            WHEN R_Percentile < 0.50 THEN 2
            WHEN R_Percentile < 0.75 THEN 3
            ELSE 4
        END AS R_Score,

        CASE
            WHEN F_Percentile < 0.25 THEN 1
            WHEN F_Percentile < 0.50 THEN 2
            WHEN F_Percentile < 0.75 THEN 3
            ELSE 4
        END AS F_Score,

        CASE
            WHEN M_Percentile < 0.25 THEN 1
            WHEN M_Percentile < 0.50 THEN 2
            WHEN M_Percentile < 0.75 THEN 3
            ELSE 4
        END AS M_Score

    FROM RFM_Percentiles
)

SELECT
    r.CustomerID,
    c.CompanyName,
    c.Country,
    r.AnalysisDate,
    r.LastOrderDate,
    r.RecencyDays AS DaysOfInactivity,
    r.Frequency AS TotalOrders,
    r.MonetaryValue AS TotalSpent,
    r.R_Score,
    r.F_Score,
    r.M_Score,
    r.R_Score + r.F_Score + r.M_Score AS Total_RFM_Score,

    CASE
        WHEN r.R_Score >= 3
             AND r.F_Score >= 3
             AND r.M_Score >= 3
            THEN 'Champions / VIP'

        WHEN r.R_Score <= 2
             AND r.F_Score >= 3
             AND r.M_Score >= 3
            THEN 'At Risk / High Value'

        WHEN r.R_Score >= 3
             AND r.F_Score <= 2
             AND r.M_Score <= 2
            THEN 'New / Occasional Customers'

        WHEN r.R_Score = 1
             AND r.F_Score = 1
             AND r.M_Score = 1
            THEN 'Inactive / Low Value'

        ELSE 'Regular Customers'
    END AS Customer_Segment,

    1 AS CustomerCount

FROM RFM_Scores r

INNER JOIN dbo.Customers c
    ON r.CustomerID = c.CustomerID;
GO


-- =========================================================================================
-- VIEW 6: EMPLOYEE SALES PERFORMANCE
-- Business Objective:
-- Measure sales performance by employee using additive order-volume and net-revenue metrics.
-- Grain: one row = one employee.
--
-- BI note:
-- Employee AOV should be calculated in the BI layer as:
-- SUM(NetRevenueGenerated) / SUM(TotalOrdersManaged)
-- and not as an average of employee-level AOVs.
-- =========================================================================================

IF OBJECT_ID(N'dbo.v_bi_employee_performance', N'V') IS NULL
    EXEC(N'CREATE VIEW dbo.v_bi_employee_performance AS SELECT 1 AS Placeholder;');
GO

ALTER VIEW dbo.v_bi_employee_performance AS

WITH OrderRevenue AS (
    SELECT
        o.OrderID,
        o.EmployeeID,

        SUM(
            CAST(od.Quantity AS DECIMAL(18,4))
            * CAST(od.UnitPrice AS DECIMAL(18,4))
            * (1 - CAST(od.Discount AS DECIMAL(18,4)))
        ) AS NetOrderRevenue

    FROM dbo.Orders o

    INNER JOIN dbo.[Order Details] od
        ON o.OrderID = od.OrderID

    GROUP BY
        o.OrderID,
        o.EmployeeID
),

EmployeeMetrics AS (
    SELECT
        EmployeeID,
        COUNT(*) AS TotalOrdersManaged,
        SUM(NetOrderRevenue) AS NetRevenueGenerated

    FROM OrderRevenue

    GROUP BY
        EmployeeID
)

SELECT
    e.EmployeeID,
    e.FirstName + ' ' + e.LastName AS SalesRep,
    e.Title AS EmployeeRole,
    em.TotalOrdersManaged,
    em.NetRevenueGenerated,

    CAST(em.NetRevenueGenerated AS DECIMAL(28,10))
        / NULLIF(
            CAST(
                SUM(em.NetRevenueGenerated) OVER ()
                AS DECIMAL(28,10)
            ),
            0
        ) AS CompanyRevenueContributionRate

FROM EmployeeMetrics em

INNER JOIN dbo.Employees e
    ON em.EmployeeID = e.EmployeeID;
GO


-- =========================================================================================
-- OPTIONAL VALIDATION QUERIES
-- Run these after the view definitions to reconcile the BI layer with validated baselines.
-- =========================================================================================

-- VIEW 1
SELECT
    COUNT(*) AS Countries,
    SUM(NumberOfOrders) AS TotalOrders,
    ROUND(SUM(NetTurnover), 2) AS TotalNetRevenue
FROM dbo.v_bi_regional_turnover_update;

-- VIEW 2
SELECT
    COUNT(*) AS RowsCount,
    COUNT(DISTINCT OrderID) AS DistinctOrders,
    ROUND(SUM(OrderAmount), 2) AS TotalNetRevenue
FROM dbo.v_bi_order_value_outliers;

-- VIEW 3
SELECT
    ROUND(SUM(NetRevenue), 2) AS TotalNetRevenue
FROM dbo.v_bi_product_performance_by_region;

-- VIEW 4
SELECT
    COUNT(*) AS ShippedOrders,
    COUNT(DISTINCT OrderID) AS DistinctOrders,
    SUM(IsShippedAfterRequiredDate) AS ShipmentsAfterRequiredDate,
    MIN(OrderToShipmentLeadTimeDays) AS MinLeadTime
FROM dbo.v_bi_shipping_performance;

-- VIEW 5
SELECT
    COUNT(*) AS ActiveCustomers,
    SUM(TotalOrders) AS TotalOrders,
    ROUND(SUM(TotalSpent), 2) AS TotalNetRevenue
FROM dbo.v_bi_customer_360;

-- VIEW 6
SELECT
    COUNT(*) AS Employees,
    SUM(TotalOrdersManaged) AS TotalOrders,
    ROUND(SUM(NetRevenueGenerated), 2) AS TotalNetRevenue,
    SUM(CompanyRevenueContributionRate) AS TotalContributionRate
FROM dbo.v_bi_employee_performance;
