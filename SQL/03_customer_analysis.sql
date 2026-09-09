USE master;
GO

/*
======================================================================
PROJECT: Northwind Business Analysis
FILE: 03_customer_analysis.sql
DIALECT: SQL Server / T-SQL
DESCRIPTION: Customer value analysis, RFM segmentation,
             inactivity monitoring, and regional basket benchmarking.
METHODOLOGY STEP: [A] Exploratory Analysis (Customer Activity)

IMPORTANT:
- Inactivity is measured relative to the latest order date in the dataset.
- It is an inactivity indicator, not an observed churn variable.
======================================================================
*/


-- ===================================================================
-- SECTION 1: CUSTOMER VALUE & RFM SEGMENTATION
-- ===================================================================

-- -------------------------------------------------------------------
-- 1.1 Top 10 high-value customers
-- -------------------------------------------------------------------
WITH CustomerRevenue AS (
    SELECT
        o.CustomerID,

        SUM(
            CAST(od.Quantity AS DECIMAL(18,4))
            * CAST(od.UnitPrice AS DECIMAL(18,4))
            * (1 - CAST(od.Discount AS DECIMAL(18,4)))
        ) AS NetRevenue

    FROM dbo.Orders o

    INNER JOIN dbo.[Order Details] od
        ON o.OrderID = od.OrderID

    GROUP BY o.CustomerID
)

SELECT TOP 10
    cr.CustomerID,
    c.CompanyName,
    c.Country,
    ROUND(cr.NetRevenue, 2) AS NetRevenue

FROM CustomerRevenue cr

INNER JOIN dbo.Customers c
    ON cr.CustomerID = c.CustomerID

ORDER BY cr.NetRevenue DESC;


-- -------------------------------------------------------------------
-- 1.2 RFM segmentation
-- PERCENT_RANK preserves ties: customers with identical metric values
-- receive the same relative rank.
-- -------------------------------------------------------------------
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

    GROUP BY OrderID
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

    GROUP BY o.CustomerID
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

RFMPercentiles AS (
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

RFMScores AS (
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

    FROM RFMPercentiles
)

SELECT
    r.CustomerID,
    c.CompanyName,
    c.Country,
    r.AnalysisDate,
    r.LastOrderDate,
    r.RecencyDays AS DaysOfInactivity,
    r.Frequency AS TotalOrders,
    ROUND(r.MonetaryValue, 2) AS TotalSpent,
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
    END AS CustomerSegment

FROM RFMScores r

INNER JOIN dbo.Customers c
    ON r.CustomerID = c.CustomerID

ORDER BY r.MonetaryValue DESC;


-- ===================================================================
-- SECTION 2: INACTIVITY & REGIONAL BASKET BENCHMARKING
-- ===================================================================

-- -------------------------------------------------------------------
-- 2.1 Customers inactive for 90+ days
--
-- The 90-day threshold is a descriptive monitoring rule.
-- It must not be interpreted as confirmed customer churn.
-- -------------------------------------------------------------------
WITH ReferenceDate AS (
    SELECT
        MAX(OrderDate) AS AnalysisDate
    FROM dbo.Orders
),

LastCustomerOrder AS (
    SELECT
        CustomerID,
        MAX(OrderDate) AS LastOrderDate
    FROM dbo.Orders
    GROUP BY CustomerID
)

SELECT
    lco.CustomerID,
    c.CompanyName,
    c.Country,
    rd.AnalysisDate,
    lco.LastOrderDate,

    DATEDIFF(
        DAY,
        lco.LastOrderDate,
        rd.AnalysisDate
    ) AS DaysOfInactivity

FROM LastCustomerOrder lco

INNER JOIN dbo.Customers c
    ON lco.CustomerID = c.CustomerID

CROSS JOIN ReferenceDate rd

WHERE DATEDIFF(
        DAY,
        lco.LastOrderDate,
        rd.AnalysisDate
      ) >= 90

ORDER BY DaysOfInactivity DESC;


-- -------------------------------------------------------------------
-- 2.2 Regional basket variance
--
-- One row in OrderAmounts = one order.
-- CustomerCountryAOV is compared with the AOV of the corresponding
-- shipping country using unrounded order values.
-- -------------------------------------------------------------------
WITH OrderAmounts AS (
    SELECT
        o.OrderID,
        o.CustomerID,
        o.ShipCountry,

        SUM(
            CAST(od.Quantity AS DECIMAL(18,4))
            * CAST(od.UnitPrice AS DECIMAL(18,4))
            * (1 - CAST(od.Discount AS DECIMAL(18,4)))
        ) AS NetOrderAmount

    FROM dbo.Orders o

    INNER JOIN dbo.[Order Details] od
        ON o.OrderID = od.OrderID

    GROUP BY
        o.OrderID,
        o.CustomerID,
        o.ShipCountry
),

CustomerCountryBaskets AS (
    SELECT
        CustomerID,
        ShipCountry,
        COUNT(*) AS CustomerOrdersInCountry,
        AVG(NetOrderAmount) AS CustomerCountryAOV

    FROM OrderAmounts

    GROUP BY
        CustomerID,
        ShipCountry
),

CountryBaskets AS (
    SELECT
        ShipCountry,
        COUNT(*) AS CountryOrders,
        AVG(NetOrderAmount) AS CountryAOV

    FROM OrderAmounts

    GROUP BY ShipCountry
)

SELECT
    ccb.CustomerID,
    c.CompanyName,
    ccb.ShipCountry,
    ccb.CustomerOrdersInCountry,

    ROUND(
        ccb.CustomerCountryAOV,
        2
    ) AS CustomerCountryAOV,

    ROUND(
        cb.CountryAOV,
        2
    ) AS CountryAOV,

    ROUND(
        ccb.CustomerCountryAOV - cb.CountryAOV,
        2
    ) AS VarianceFromCountryAOV

FROM CustomerCountryBaskets ccb

INNER JOIN CountryBaskets cb
    ON ccb.ShipCountry = cb.ShipCountry

INNER JOIN dbo.Customers c
    ON ccb.CustomerID = c.CustomerID

ORDER BY
    ccb.ShipCountry,
    ccb.CustomerCountryAOV DESC;
