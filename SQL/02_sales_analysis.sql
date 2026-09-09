USE master;
GO

/*
======================================================================
PROJECT: Northwind Business Analysis
FILE: 02_sales_analysis.sql
DIALECT: SQL Server / T-SQL
DESCRIPTION: Sales revenue trends, month-over-month growth,
             cumulative revenue, and customer acquisition dynamics.
METHODOLOGY STEP: [A] Exploratory Analysis (Sales Performance)

IMPORTANT:
- Revenue is calculated using transaction-time UnitPrice and Discount.
- The final incomplete calendar month is excluded from monthly trend
  comparisons to avoid distorted month-over-month interpretation.
======================================================================
*/


-- ===================================================================
-- SECTION 1: MONTHLY REVENUE TRENDS & GROWTH
-- ===================================================================

WITH DataCoverage AS (
    SELECT
        MAX(OrderDate) AS MaxOrderDate
    FROM dbo.Orders
),

TrendBoundary AS (
    SELECT
        CASE
            WHEN CAST(MaxOrderDate AS DATE) = EOMONTH(MaxOrderDate)
                THEN DATEADD(DAY, 1, EOMONTH(MaxOrderDate))
            ELSE DATEFROMPARTS(
                YEAR(MaxOrderDate),
                MONTH(MaxOrderDate),
                1
            )
        END AS TrendCutoffExclusive
    FROM DataCoverage
),

MonthlyRevenue AS (
    SELECT
        DATEFROMPARTS(
            YEAR(o.OrderDate),
            MONTH(o.OrderDate),
            1
        ) AS OrderMonth,

        SUM(
            CAST(od.Quantity AS DECIMAL(18,4))
            * CAST(od.UnitPrice AS DECIMAL(18,4))
            * (1 - CAST(od.Discount AS DECIMAL(18,4)))
        ) AS NetRevenue

    FROM dbo.[Order Details] od

    INNER JOIN dbo.Orders o
        ON od.OrderID = o.OrderID

    CROSS JOIN TrendBoundary tb

    WHERE o.OrderDate < tb.TrendCutoffExclusive

    GROUP BY
        DATEFROMPARTS(
            YEAR(o.OrderDate),
            MONTH(o.OrderDate),
            1
        )
),

TrendMetrics AS (
    SELECT
        OrderMonth,
        NetRevenue,

        LAG(NetRevenue) OVER (
            ORDER BY OrderMonth
        ) AS PreviousMonthRevenue

    FROM MonthlyRevenue
)

SELECT
    OrderMonth,

    ROUND(NetRevenue, 2) AS MonthlyNetRevenue,

    ROUND(
        SUM(NetRevenue) OVER (
            ORDER BY OrderMonth
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ),
        2
    ) AS CumulativeNetRevenue,

    ROUND(
        100.0
        * (NetRevenue - PreviousMonthRevenue)
        / NULLIF(PreviousMonthRevenue, 0),
        2
    ) AS MoMGrowthPct

FROM TrendMetrics

ORDER BY OrderMonth;


-- ===================================================================
-- SECTION 2: CUSTOMER ACQUISITION DYNAMICS
-- ===================================================================

-- -------------------------------------------------------------------
-- 2.1 Monthly acquisition
-- A customer is considered acquired in the month of their first order.
-- -------------------------------------------------------------------
WITH FirstOrders AS (
    SELECT
        CustomerID,
        MIN(OrderDate) AS FirstOrderDate
    FROM dbo.Orders
    GROUP BY CustomerID
),

MonthlyAcquisition AS (
    SELECT
        DATEFROMPARTS(
            YEAR(FirstOrderDate),
            MONTH(FirstOrderDate),
            1
        ) AS AcquisitionMonth,

        COUNT(*) AS NewCustomers

    FROM FirstOrders

    GROUP BY
        DATEFROMPARTS(
            YEAR(FirstOrderDate),
            MONTH(FirstOrderDate),
            1
        )
)

SELECT
    AcquisitionMonth,
    NewCustomers,

    SUM(NewCustomers) OVER (
        ORDER BY AcquisitionMonth
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS CumulativeAcquiredCustomers

FROM MonthlyAcquisition

ORDER BY AcquisitionMonth;


-- -------------------------------------------------------------------
-- 2.2 Annual acquisition summary
-- -------------------------------------------------------------------
WITH FirstOrders AS (
    SELECT
        CustomerID,
        MIN(OrderDate) AS FirstOrderDate
    FROM dbo.Orders
    GROUP BY CustomerID
)

SELECT
    YEAR(FirstOrderDate) AS AcquisitionYear,
    COUNT(*) AS NewCustomers

FROM FirstOrders

GROUP BY YEAR(FirstOrderDate)

ORDER BY AcquisitionYear;
