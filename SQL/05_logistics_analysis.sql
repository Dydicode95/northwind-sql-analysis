USE master;
GO

/*
======================================================================
PROJECT: Northwind Business Analysis
FILE: 05_logistics_analysis.sql
DIALECT: SQL Server / T-SQL
DESCRIPTION: Carrier benchmarking, order-to-shipment lead times,
             shipment timing, destination analysis, freight amounts,
             and logistics trends.
METHODOLOGY STEP: [A] Exploratory Analysis (Operations & Logistics)

IMPORTANT:
- ShippedDate is the shipment date, not the customer delivery date.
- Freight is treated as the freight amount recorded on the order; the
  dataset does not establish that it is an accounting cost.
======================================================================
*/


-- ===================================================================
-- SECTION 1: CARRIER BENCHMARKING
-- ===================================================================

WITH ValidShipments AS (
    SELECT
        o.OrderID,
        o.OrderDate,
        o.RequiredDate,
        o.ShippedDate,
        o.Freight AS FreightAmount,
        s.ShipperID,
        s.CompanyName AS ShipperName,

        DATEDIFF(
            DAY,
            o.OrderDate,
            o.ShippedDate
        ) AS OrderToShipmentLeadTimeDays

    FROM dbo.Orders o

    INNER JOIN dbo.Shippers s
        ON o.ShipVia = s.ShipperID

    WHERE o.ShippedDate IS NOT NULL
      AND o.ShippedDate >= o.OrderDate
)

SELECT
    ShipperID,
    ShipperName,
    COUNT(*) AS TotalShipments,

    ROUND(
        AVG(
            CAST(OrderToShipmentLeadTimeDays AS DECIMAL(18,4))
        ),
        2
    ) AS AvgOrderToShipmentLeadTimeDays,

    ROUND(
        AVG(
            CAST(FreightAmount AS DECIMAL(18,4))
        ),
        2
    ) AS AvgFreightAmount,

    SUM(
        CASE
            WHEN RequiredDate IS NOT NULL
                 AND ShippedDate > RequiredDate
                THEN 1
            ELSE 0
        END
    ) AS ShipmentsAfterRequiredDate,

    SUM(
        CASE
            WHEN RequiredDate IS NULL THEN 1
            ELSE 0
        END
    ) AS MissingRequiredDateCount,

    ROUND(
        100.0
        * AVG(
            CASE
                WHEN RequiredDate IS NULL THEN NULL
                WHEN ShippedDate > RequiredDate THEN 1.0
                ELSE 0.0
            END
        ),
        2
    ) AS ShipmentAfterRequiredDateRatePct

FROM ValidShipments

GROUP BY
    ShipperID,
    ShipperName

ORDER BY
    AvgOrderToShipmentLeadTimeDays,
    ShipperName;


-- ===================================================================
-- SECTION 2: DESTINATION-LEVEL LOGISTICS
-- ===================================================================

WITH ValidShipments AS (
    SELECT
        o.OrderID,
        o.ShipCountry,
        o.OrderDate,
        o.RequiredDate,
        o.ShippedDate,
        o.Freight AS FreightAmount,

        DATEDIFF(
            DAY,
            o.OrderDate,
            o.ShippedDate
        ) AS OrderToShipmentLeadTimeDays

    FROM dbo.Orders o

    WHERE o.ShippedDate IS NOT NULL
      AND o.ShippedDate >= o.OrderDate
)

SELECT
    ShipCountry,
    COUNT(*) AS TotalShipments,

    ROUND(
        SUM(
            CAST(FreightAmount AS DECIMAL(18,4))
        ),
        2
    ) AS TotalFreightAmount,

    ROUND(
        AVG(
            CAST(FreightAmount AS DECIMAL(18,4))
        ),
        2
    ) AS AvgFreightAmount,

    ROUND(
        AVG(
            CAST(OrderToShipmentLeadTimeDays AS DECIMAL(18,4))
        ),
        2
    ) AS AvgOrderToShipmentLeadTimeDays,

    ROUND(
        100.0
        * AVG(
            CASE
                WHEN RequiredDate IS NULL THEN NULL
                WHEN ShippedDate > RequiredDate THEN 1.0
                ELSE 0.0
            END
        ),
        2
    ) AS ShipmentAfterRequiredDateRatePct

FROM ValidShipments

GROUP BY ShipCountry

ORDER BY
    AvgOrderToShipmentLeadTimeDays DESC,
    ShipCountry;


-- ===================================================================
-- SECTION 3: MONTHLY LOGISTICS TRENDS
-- ===================================================================

-- The final incomplete calendar month is excluded to avoid comparing a
-- partial month with complete months.

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

ValidShipments AS (
    SELECT
        DATEFROMPARTS(
            YEAR(o.OrderDate),
            MONTH(o.OrderDate),
            1
        ) AS OrderMonth,

        s.CompanyName AS ShipperName,
        o.RequiredDate,
        o.ShippedDate,

        DATEDIFF(
            DAY,
            o.OrderDate,
            o.ShippedDate
        ) AS OrderToShipmentLeadTimeDays

    FROM dbo.Orders o

    INNER JOIN dbo.Shippers s
        ON o.ShipVia = s.ShipperID

    CROSS JOIN TrendBoundary tb

    WHERE o.ShippedDate IS NOT NULL
      AND o.ShippedDate >= o.OrderDate
      AND o.OrderDate < tb.TrendCutoffExclusive
)

SELECT
    OrderMonth,
    ShipperName,
    COUNT(*) AS TotalShipments,

    ROUND(
        AVG(
            CAST(OrderToShipmentLeadTimeDays AS DECIMAL(18,4))
        ),
        2
    ) AS AvgOrderToShipmentLeadTimeDays,

    ROUND(
        100.0
        * AVG(
            CASE
                WHEN RequiredDate IS NULL THEN NULL
                WHEN ShippedDate > RequiredDate THEN 1.0
                ELSE 0.0
            END
        ),
        2
    ) AS ShipmentAfterRequiredDateRatePct

FROM ValidShipments

GROUP BY
    OrderMonth,
    ShipperName

ORDER BY
    OrderMonth,
    ShipperName;


-- ===================================================================
-- SECTION 4: FREIGHT AMOUNT TO NET REVENUE RATIO
-- ===================================================================

-- This ratio describes freight amount relative to net revenue.
-- It should not be interpreted as a profit-margin calculation.

WITH OrderRevenue AS (
    SELECT
        OrderID,

        SUM(
            CAST(Quantity AS DECIMAL(18,4))
            * CAST(UnitPrice AS DECIMAL(18,4))
            * (1 - CAST(Discount AS DECIMAL(18,4)))
        ) AS NetRevenue

    FROM dbo.[Order Details]

    GROUP BY OrderID
)

SELECT
    o.ShipCountry,
    COUNT(*) AS TotalShippedOrders,

    ROUND(
        SUM(r.NetRevenue),
        2
    ) AS TotalNetRevenue,

    ROUND(
        SUM(
            CAST(o.Freight AS DECIMAL(18,4))
        ),
        2
    ) AS TotalFreightAmount,

    ROUND(
        100.0
        * SUM(CAST(o.Freight AS DECIMAL(18,4)))
        / NULLIF(SUM(r.NetRevenue), 0),
        2
    ) AS FreightAmountToNetRevenuePct

FROM dbo.Orders o

INNER JOIN OrderRevenue r
    ON o.OrderID = r.OrderID

WHERE o.ShippedDate IS NOT NULL
  AND o.ShippedDate >= o.OrderDate

GROUP BY o.ShipCountry

ORDER BY
    FreightAmountToNetRevenuePct DESC,
    o.ShipCountry;
