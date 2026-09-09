USE master;
GO

/*
======================================================================
PROJECT: Northwind Business Analysis — V2
FILE: 04_product_analysis.sql
DIALECT: SQL Server / T-SQL
DESCRIPTION: Product and category performance analysis:
             revenue, volume, order penetration, discount exposure,
             category contribution, rankings, and monthly trends.
METHODOLOGY STEP: [A] Exploratory Analysis (Product Performance)

IMPORTANT ANALYTICAL NOTES
- Revenue is calculated from Order Details, using the transaction-time
  UnitPrice and Discount (not the current catalog price in Products).
- Net Revenue = Quantity * UnitPrice * (1 - Discount)
- "Discount relationship" below is descriptive. It does NOT prove
  price elasticity or a causal promotional effect.
======================================================================
*/


-- ===================================================================
-- SECTION 0: PRODUCT REVENUE RECONCILIATION
-- Business question:
-- Does product-level revenue reconcile with the validated company total?
-- Expected Northwind V2 Net Revenue: approximately 1,265,793.22
-- ===================================================================

WITH ProductRevenue AS (
    SELECT
        od.ProductID,
        SUM(
            CAST(od.Quantity AS DECIMAL(18,4))
            * CAST(od.UnitPrice AS DECIMAL(18,4))
            * (1 - CAST(od.Discount AS DECIMAL(18,4)))
        ) AS NetRevenue
    FROM dbo.[Order Details] od
    GROUP BY od.ProductID
)
SELECT
    ROUND(SUM(NetRevenue), 2) AS ProductLevelNetRevenue,
    CAST(1265793.22 AS DECIMAL(18,2)) AS ValidatedGlobalNetRevenue,
    CASE
        WHEN ABS(
            ROUND(SUM(NetRevenue), 2)
            - CAST(1265793.22 AS DECIMAL(18,2))
        ) < 0.01
        THEN 'PASS'
        ELSE 'CHECK'
    END AS ReconciliationStatus
FROM ProductRevenue;


-- ===================================================================
-- SECTION 1: PRODUCT PERFORMANCE LEADERBOARD
-- Business questions:
-- Which products generate the most revenue?
-- Which products generate the most physical volume?
-- How frequently does each product appear in customer orders?
-- ===================================================================

WITH ProductMetrics AS (
    SELECT
        p.ProductID,
        p.ProductName,
        c.CategoryName,

        COUNT(DISTINCT od.OrderID) AS OrdersContainingProduct,
        SUM(CAST(od.Quantity AS BIGINT)) AS UnitsSold,

        SUM(
            CAST(od.Quantity AS DECIMAL(18,4))
            * CAST(od.UnitPrice AS DECIMAL(18,4))
        ) AS GrossRevenue,

        SUM(
            CAST(od.Quantity AS DECIMAL(18,4))
            * CAST(od.UnitPrice AS DECIMAL(18,4))
            * CAST(od.Discount AS DECIMAL(18,4))
        ) AS DiscountAmount,

        SUM(
            CAST(od.Quantity AS DECIMAL(18,4))
            * CAST(od.UnitPrice AS DECIMAL(18,4))
            * (1 - CAST(od.Discount AS DECIMAL(18,4)))
        ) AS NetRevenue

    FROM dbo.[Order Details] od
    INNER JOIN dbo.Products p
        ON od.ProductID = p.ProductID
    INNER JOIN dbo.Categories c
        ON p.CategoryID = c.CategoryID
    GROUP BY
        p.ProductID,
        p.ProductName,
        c.CategoryName
),
RankedProducts AS (
    SELECT
        *,
        RANK() OVER (ORDER BY NetRevenue DESC) AS RevenueRank,
        RANK() OVER (ORDER BY UnitsSold DESC) AS VolumeRank,
        SUM(NetRevenue) OVER () AS CompanyNetRevenue
    FROM ProductMetrics
)
SELECT
    ProductID,
    ProductName,
    CategoryName,
    OrdersContainingProduct,
    UnitsSold,

    ROUND(GrossRevenue, 2) AS GrossRevenue,
    ROUND(DiscountAmount, 2) AS DiscountAmount,
    ROUND(NetRevenue, 2) AS NetRevenue,

    ROUND(
        100.0 * NetRevenue / NULLIF(CompanyNetRevenue, 0),
        2
    ) AS CompanyRevenueSharePct,

    ROUND(
        NetRevenue / NULLIF(OrdersContainingProduct, 0),
        2
    ) AS RevenuePerContainingOrder,

    ROUND(
        NetRevenue / NULLIF(UnitsSold, 0),
        2
    ) AS NetRevenuePerUnit,

    ROUND(
        100.0 * DiscountAmount / NULLIF(GrossRevenue, 0),
        2
    ) AS EffectiveDiscountRatePct,

    RevenueRank,
    VolumeRank

FROM RankedProducts
ORDER BY RevenueRank, ProductID;


-- ===================================================================
-- SECTION 2: REVENUE DRIVERS VS VOLUME DRIVERS
-- Business question:
-- Do the products that sell the most units also generate the most revenue?
--
-- Interpretation:
-- "Dual Leader"    = Top 10 in both revenue and volume.
-- "Revenue Driver" = Top 10 revenue, but not Top 10 volume.
-- "Volume Driver"  = Top 10 volume, but not Top 10 revenue.
-- "Other"          = Outside both Top 10 lists.
--
-- This classification is transparent and descriptive; it is not a model.
-- ===================================================================

WITH ProductMetrics AS (
    SELECT
        p.ProductID,
        p.ProductName,
        c.CategoryName,
        SUM(CAST(od.Quantity AS BIGINT)) AS UnitsSold,
        SUM(
            CAST(od.Quantity AS DECIMAL(18,4))
            * CAST(od.UnitPrice AS DECIMAL(18,4))
            * (1 - CAST(od.Discount AS DECIMAL(18,4)))
        ) AS NetRevenue
    FROM dbo.[Order Details] od
    INNER JOIN dbo.Products p
        ON od.ProductID = p.ProductID
    INNER JOIN dbo.Categories c
        ON p.CategoryID = c.CategoryID
    GROUP BY
        p.ProductID,
        p.ProductName,
        c.CategoryName
),
ProductRanks AS (
    SELECT
        *,
        RANK() OVER (ORDER BY NetRevenue DESC) AS RevenueRank,
        RANK() OVER (ORDER BY UnitsSold DESC) AS VolumeRank
    FROM ProductMetrics
)
SELECT
    ProductID,
    ProductName,
    CategoryName,
    ROUND(NetRevenue, 2) AS NetRevenue,
    UnitsSold,
    RevenueRank,
    VolumeRank,
    VolumeRank - RevenueRank AS RankGap,
    CASE
        WHEN RevenueRank <= 10 AND VolumeRank <= 10
            THEN 'Dual Leader'
        WHEN RevenueRank <= 10 AND VolumeRank > 10
            THEN 'Revenue Driver'
        WHEN VolumeRank <= 10 AND RevenueRank > 10
            THEN 'Volume Driver'
        ELSE 'Other'
    END AS ProductPerformanceProfile
FROM ProductRanks
ORDER BY
    CASE
        WHEN RevenueRank <= 10 OR VolumeRank <= 10 THEN 0
        ELSE 1
    END,
    RevenueRank,
    VolumeRank;


-- ===================================================================
-- SECTION 3: CATEGORY PERFORMANCE & REVENUE MIX
-- Business questions:
-- Which categories contribute most to company revenue and volume?
-- How diversified is revenue across categories?
-- ===================================================================

WITH CategoryMetrics AS (
    SELECT
        c.CategoryID,
        c.CategoryName,

        COUNT(DISTINCT p.ProductID) AS ProductsSold,
        COUNT(DISTINCT od.OrderID) AS OrdersContainingCategory,
        SUM(CAST(od.Quantity AS BIGINT)) AS UnitsSold,

        SUM(
            CAST(od.Quantity AS DECIMAL(18,4))
            * CAST(od.UnitPrice AS DECIMAL(18,4))
        ) AS GrossRevenue,

        SUM(
            CAST(od.Quantity AS DECIMAL(18,4))
            * CAST(od.UnitPrice AS DECIMAL(18,4))
            * CAST(od.Discount AS DECIMAL(18,4))
        ) AS DiscountAmount,

        SUM(
            CAST(od.Quantity AS DECIMAL(18,4))
            * CAST(od.UnitPrice AS DECIMAL(18,4))
            * (1 - CAST(od.Discount AS DECIMAL(18,4)))
        ) AS NetRevenue

    FROM dbo.[Order Details] od
    INNER JOIN dbo.Products p
        ON od.ProductID = p.ProductID
    INNER JOIN dbo.Categories c
        ON p.CategoryID = c.CategoryID
    GROUP BY
        c.CategoryID,
        c.CategoryName
),
RankedCategories AS (
    SELECT
        *,
        SUM(NetRevenue) OVER () AS CompanyNetRevenue,
        RANK() OVER (ORDER BY NetRevenue DESC) AS RevenueRank,
        RANK() OVER (ORDER BY UnitsSold DESC) AS VolumeRank
    FROM CategoryMetrics
)
SELECT
    CategoryID,
    CategoryName,
    ProductsSold,
    OrdersContainingCategory,
    UnitsSold,
    ROUND(GrossRevenue, 2) AS GrossRevenue,
    ROUND(DiscountAmount, 2) AS DiscountAmount,
    ROUND(NetRevenue, 2) AS NetRevenue,
    ROUND(
        100.0 * NetRevenue / NULLIF(CompanyNetRevenue, 0),
        2
    ) AS CompanyRevenueSharePct,
    ROUND(
        NetRevenue / NULLIF(ProductsSold, 0),
        2
    ) AS RevenuePerProduct,
    RevenueRank,
    VolumeRank
FROM RankedCategories
ORDER BY RevenueRank;


-- ===================================================================
-- SECTION 4: PRODUCT CONTRIBUTION WITHIN EACH CATEGORY
-- Business question:
-- Which products are the pillars of their own category?
-- ===================================================================

WITH ProductCategoryRevenue AS (
    SELECT
        c.CategoryID,
        c.CategoryName,
        p.ProductID,
        p.ProductName,
        SUM(CAST(od.Quantity AS BIGINT)) AS UnitsSold,
        SUM(
            CAST(od.Quantity AS DECIMAL(18,4))
            * CAST(od.UnitPrice AS DECIMAL(18,4))
            * (1 - CAST(od.Discount AS DECIMAL(18,4)))
        ) AS NetRevenue
    FROM dbo.[Order Details] od
    INNER JOIN dbo.Products p
        ON od.ProductID = p.ProductID
    INNER JOIN dbo.Categories c
        ON p.CategoryID = c.CategoryID
    GROUP BY
        c.CategoryID,
        c.CategoryName,
        p.ProductID,
        p.ProductName
),
CategoryContribution AS (
    SELECT
        *,
        SUM(NetRevenue) OVER (
            PARTITION BY CategoryID
        ) AS CategoryNetRevenue,
        RANK() OVER (
            PARTITION BY CategoryID
            ORDER BY NetRevenue DESC
        ) AS RevenueRankWithinCategory
    FROM ProductCategoryRevenue
)
SELECT
    CategoryID,
    CategoryName,
    ProductID,
    ProductName,
    UnitsSold,
    ROUND(NetRevenue, 2) AS NetRevenue,
    ROUND(
        100.0 * NetRevenue / NULLIF(CategoryNetRevenue, 0),
        2
    ) AS CategoryRevenueSharePct,
    RevenueRankWithinCategory
FROM CategoryContribution
ORDER BY
    CategoryName,
    RevenueRankWithinCategory,
    ProductID;


-- ===================================================================
-- SECTION 5: DISCOUNT–VOLUME RELATIONSHIP
-- Business question:
-- How do sales volume and net revenue differ across discount bands?
--
-- IMPORTANT:
-- This is a descriptive comparison only.
-- It does NOT estimate price elasticity and does NOT establish causality.
-- Product mix, seasonality, customer mix, and order size may confound results.
-- ===================================================================

WITH LineMetrics AS (
    SELECT
        od.OrderID,
        od.ProductID,
        CAST(od.Quantity AS DECIMAL(18,4)) AS Quantity,
        CAST(od.UnitPrice AS DECIMAL(18,4)) AS UnitPrice,
        CAST(od.Discount AS DECIMAL(18,4)) AS Discount,
        CAST(od.Quantity AS DECIMAL(18,4))
            * CAST(od.UnitPrice AS DECIMAL(18,4)) AS GrossLineRevenue,
        CAST(od.Quantity AS DECIMAL(18,4))
            * CAST(od.UnitPrice AS DECIMAL(18,4))
            * CAST(od.Discount AS DECIMAL(18,4)) AS DiscountAmount,
        CAST(od.Quantity AS DECIMAL(18,4))
            * CAST(od.UnitPrice AS DECIMAL(18,4))
            * (1 - CAST(od.Discount AS DECIMAL(18,4))) AS NetLineRevenue,
        CASE
            WHEN od.Discount = 0 THEN '0%'
            WHEN od.Discount <= 0.10 THEN '>0% to 10%'
            WHEN od.Discount <= 0.20 THEN '>10% to 20%'
            ELSE '>20%'
        END AS DiscountBand,
        CASE
            WHEN od.Discount = 0 THEN 1
            WHEN od.Discount <= 0.10 THEN 2
            WHEN od.Discount <= 0.20 THEN 3
            ELSE 4
        END AS DiscountBandOrder
    FROM dbo.[Order Details] od
)
SELECT
    DiscountBand,
    COUNT(*) AS OrderLines,
    COUNT(DISTINCT OrderID) AS DistinctOrders,
    COUNT(DISTINCT ProductID) AS DistinctProducts,
    SUM(Quantity) AS UnitsSold,
    ROUND(AVG(Quantity), 2) AS AverageUnitsPerOrderLine,
    ROUND(SUM(GrossLineRevenue), 2) AS GrossRevenue,
    ROUND(SUM(DiscountAmount), 2) AS DiscountAmount,
    ROUND(SUM(NetLineRevenue), 2) AS NetRevenue,
    ROUND(
        100.0 * SUM(DiscountAmount)
        / NULLIF(SUM(GrossLineRevenue), 0),
        2
    ) AS EffectiveDiscountRatePct
FROM LineMetrics
GROUP BY
    DiscountBand,
    DiscountBandOrder
ORDER BY DiscountBandOrder;


-- ===================================================================
-- SECTION 6: PRODUCT DISCOUNT EXPOSURE
-- Business question:
-- Which products rely most heavily on discounted sales?
-- ===================================================================

WITH ProductDiscountMetrics AS (
    SELECT
        p.ProductID,
        p.ProductName,
        c.CategoryName,

        SUM(CAST(od.Quantity AS BIGINT)) AS UnitsSold,

        SUM(
            CASE
                WHEN od.Discount > 0
                THEN CAST(od.Quantity AS BIGINT)
                ELSE 0
            END
        ) AS DiscountedUnits,

        SUM(
            CASE
                WHEN od.Discount = 0
                THEN CAST(od.Quantity AS BIGINT)
                ELSE 0
            END
        ) AS FullPriceUnits,

        SUM(
            CAST(od.Quantity AS DECIMAL(18,4))
            * CAST(od.UnitPrice AS DECIMAL(18,4))
        ) AS GrossRevenue,

        SUM(
            CAST(od.Quantity AS DECIMAL(18,4))
            * CAST(od.UnitPrice AS DECIMAL(18,4))
            * CAST(od.Discount AS DECIMAL(18,4))
        ) AS DiscountAmount,

        SUM(
            CAST(od.Quantity AS DECIMAL(18,4))
            * CAST(od.UnitPrice AS DECIMAL(18,4))
            * (1 - CAST(od.Discount AS DECIMAL(18,4)))
        ) AS NetRevenue

    FROM dbo.[Order Details] od
    INNER JOIN dbo.Products p
        ON od.ProductID = p.ProductID
    INNER JOIN dbo.Categories c
        ON p.CategoryID = c.CategoryID
    GROUP BY
        p.ProductID,
        p.ProductName,
        c.CategoryName
)
SELECT
    ProductID,
    ProductName,
    CategoryName,
    UnitsSold,
    DiscountedUnits,
    FullPriceUnits,
    ROUND(
        100.0 * DiscountedUnits / NULLIF(UnitsSold, 0),
        2
    ) AS DiscountedUnitSharePct,
    ROUND(GrossRevenue, 2) AS GrossRevenue,
    ROUND(DiscountAmount, 2) AS DiscountAmount,
    ROUND(NetRevenue, 2) AS NetRevenue,
    ROUND(
        100.0 * DiscountAmount / NULLIF(GrossRevenue, 0),
        2
    ) AS EffectiveDiscountRatePct
FROM ProductDiscountMetrics
ORDER BY
    DiscountedUnitSharePct DESC,
    NetRevenue DESC;


-- ===================================================================
-- SECTION 7: MONTHLY CATEGORY TRENDS
-- Business questions:
-- How does category revenue evolve across complete calendar months?
-- Which categories lead revenue each month?
--
-- Data-quality note:
-- The final incomplete calendar month is excluded dynamically so that
-- month-over-month comparisons use complete calendar months only.
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

MonthlyCategoryRevenue AS (
    SELECT
        DATEFROMPARTS(
            YEAR(o.OrderDate),
            MONTH(o.OrderDate),
            1
        ) AS OrderMonth,
        c.CategoryID,
        c.CategoryName,
        SUM(CAST(od.Quantity AS BIGINT)) AS UnitsSold,
        SUM(
            CAST(od.Quantity AS DECIMAL(18,4))
            * CAST(od.UnitPrice AS DECIMAL(18,4))
            * (1 - CAST(od.Discount AS DECIMAL(18,4)))
        ) AS NetRevenue
    FROM dbo.Orders o
    INNER JOIN dbo.[Order Details] od
        ON o.OrderID = od.OrderID
    INNER JOIN dbo.Products p
        ON od.ProductID = p.ProductID
    INNER JOIN dbo.Categories c
        ON p.CategoryID = c.CategoryID
    CROSS JOIN TrendBoundary tb
    WHERE o.OrderDate < tb.TrendCutoffExclusive
    GROUP BY
        DATEFROMPARTS(
            YEAR(o.OrderDate),
            MONTH(o.OrderDate),
            1
        ),
        c.CategoryID,
        c.CategoryName
),

TrendMetrics AS (
    SELECT
        *,
        LAG(NetRevenue) OVER (
            PARTITION BY CategoryID
            ORDER BY OrderMonth
        ) AS PreviousMonthRevenue,
        RANK() OVER (
            PARTITION BY OrderMonth
            ORDER BY NetRevenue DESC
        ) AS MonthlyRevenueRank
    FROM MonthlyCategoryRevenue
)

SELECT
    OrderMonth,
    CategoryID,
    CategoryName,
    UnitsSold,
    ROUND(NetRevenue, 2) AS NetRevenue,
    ROUND(
        100.0
        * (NetRevenue - PreviousMonthRevenue)
        / NULLIF(PreviousMonthRevenue, 0),
        2
    ) AS MoMGrowthPct,
    MonthlyRevenueRank
FROM TrendMetrics
ORDER BY
    OrderMonth,
    MonthlyRevenueRank,
    CategoryID;


-- ===================================================================
-- SECTION 8: CURRENT PRODUCT CATALOG SNAPSHOT
-- Business question:
-- What does the CURRENT Products-table inventory snapshot look like?
--
-- CAUTION:
-- UnitsInStock / UnitsOnOrder / ReorderLevel are current catalog fields,
-- not historical inventory measurements. Do not use them to claim that
-- a historical stock-out caused historical sales performance.
-- ===================================================================

SELECT
    p.ProductID,
    p.ProductName,
    c.CategoryName,
    p.UnitPrice AS CurrentCatalogUnitPrice,
    p.UnitsInStock,
    p.UnitsOnOrder,
    p.ReorderLevel,
    p.Discontinued,
    CASE
        WHEN p.Discontinued = 1 THEN 'Discontinued'
        WHEN p.UnitsInStock = 0 THEN 'Out of Stock'
        WHEN p.UnitsInStock <= p.ReorderLevel THEN 'At / Below Reorder Level'
        ELSE 'Stock Above Reorder Level'
    END AS CurrentInventoryStatus
FROM dbo.Products p
INNER JOIN dbo.Categories c
    ON p.CategoryID = c.CategoryID
ORDER BY
    CurrentInventoryStatus,
    p.UnitsInStock,
    p.ProductName;
