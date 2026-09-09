USE master;
GO

/*
======================================================================
PROJECT: Northwind Business Analysis
FILE: 06_employee_analysis.sql
DIALECT: SQL Server / T-SQL
DESCRIPTION: Sales-force performance, revenue contribution,
             order efficiency, and customer-geography footprint.
METHODOLOGY STEP: [A] Exploratory Analysis (Employee Performance)
======================================================================
*/


-- ===================================================================
-- SECTION 1: SALES FORCE LEADERBOARD
-- ===================================================================

-- -------------------------------------------------------------------
-- 1.1 Revenue contribution and order efficiency by sales representative
-- One row = one employee.
-- AverageRevenuePerOrder is valid at this grain; do not average it across employees.
-- -------------------------------------------------------------------
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

    GROUP BY EmployeeID
)

SELECT
    e.EmployeeID,
    e.FirstName + ' ' + e.LastName AS SalesRep,
    e.Title AS EmployeeRole,

    em.TotalOrdersManaged,

    ROUND(
        em.NetRevenueGenerated,
        2
    ) AS NetRevenueGenerated,

    ROUND(
        em.NetRevenueGenerated
        / NULLIF(em.TotalOrdersManaged, 0),
        2
    ) AS AverageRevenuePerOrder,

    ROUND(
        100.0
        * em.NetRevenueGenerated
        / NULLIF(
            SUM(em.NetRevenueGenerated) OVER (),
            0
        ),
        2
    ) AS CompanyRevenueContributionPct,

    RANK() OVER (
        ORDER BY em.NetRevenueGenerated DESC
    ) AS RevenueRank

FROM EmployeeMetrics em

INNER JOIN dbo.Employees e
    ON em.EmployeeID = e.EmployeeID

ORDER BY
    RevenueRank,
    e.EmployeeID;


-- -------------------------------------------------------------------
-- 1.2 Top performer revenue contribution
-- KPI is calculated dynamically; no percentage is hard-coded.
-- -------------------------------------------------------------------
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

    GROUP BY EmployeeID
),

RankedEmployees AS (
    SELECT
        *,

        SUM(NetRevenueGenerated) OVER () AS CompanyNetRevenue,

        RANK() OVER (
            ORDER BY NetRevenueGenerated DESC
        ) AS RevenueRank

    FROM EmployeeMetrics
)

SELECT
    re.EmployeeID,
    e.FirstName + ' ' + e.LastName AS SalesRep,

    ROUND(
        re.NetRevenueGenerated,
        2
    ) AS TopPerformerRevenue,

    ROUND(
        re.CompanyNetRevenue,
        2
    ) AS CompanyNetRevenue,

    ROUND(
        100.0
        * re.NetRevenueGenerated
        / NULLIF(re.CompanyNetRevenue, 0),
        2
    ) AS CompanyRevenueContributionPct

FROM RankedEmployees re

INNER JOIN dbo.Employees e
    ON re.EmployeeID = e.EmployeeID

WHERE re.RevenueRank = 1;


-- ===================================================================
-- SECTION 2: EMPLOYEE CUSTOMER-GEOGRAPHY FOOTPRINT
-- ===================================================================

-- Customer country is used deliberately here to describe the geographic
-- origin of customers handled by each employee.
-- One row = one employee x customer country.

WITH OrderRevenue AS (
    SELECT
        o.OrderID,
        o.EmployeeID,
        o.CustomerID,

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
        o.EmployeeID,
        o.CustomerID
)

SELECT
    e.EmployeeID,
    e.FirstName + ' ' + e.LastName AS SalesRep,
    c.Country AS CustomerCountry,

    COUNT(*) AS TotalOrders,

    ROUND(
        SUM(orv.NetOrderRevenue),
        2
    ) AS NetRevenueGenerated,

    ROUND(
        100.0
        * SUM(orv.NetOrderRevenue)
        / NULLIF(
            SUM(SUM(orv.NetOrderRevenue)) OVER (
                PARTITION BY e.EmployeeID
            ),
            0
        ),
        2
    ) AS EmployeeRevenueShareInCountryPct

FROM OrderRevenue orv

INNER JOIN dbo.Employees e
    ON orv.EmployeeID = e.EmployeeID

INNER JOIN dbo.Customers c
    ON orv.CustomerID = c.CustomerID

GROUP BY
    e.EmployeeID,
    e.FirstName,
    e.LastName,
    c.Country

ORDER BY
    SalesRep,
    NetRevenueGenerated DESC;
