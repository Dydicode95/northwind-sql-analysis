/*
======================================================================
PROJECT: Northwind Business Analysis
FILE: 04_product_analysis.sql
DESCRIPTION: Product Performance Revenue, Rank/Dense_Rank Benchmarking, 
             Discount Impact Analysis, and Market Basket Co-Purchasing.
METHODOLOGY STEP: [A] Exploratory Analysis (Product & Category)
======================================================================
*/

-- ===================================================================
-- SECTION 1: PRODUCT PERFORMANCE & REVENUE RANKING
-- ===================================================================

-- -------------------------------------------------------------------
-- 1.1. Absolute Product Revenue & Quantities Sold
-- Objective: Extract raw financial performance and volume metrics 
--            for every product in the catalog.
-- -------------------------------------------------------------------
SELECT 
    od.ProductID, 
    SUM(od.Quantity * od.UnitPrice * (1 - od.Discount)) AS RevenuePerProduct, 
    SUM(od.Quantity) AS TotalQuantitySold 
FROM dbo.[Order Details] od 
GROUP BY od.ProductID
ORDER BY RevenuePerProduct DESC;


-- -------------------------------------------------------------------
-- 1.2. Top/Flop Analysis Using Window Ranking Functions
-- Objective: Apply RANK() and DENSE_RANK() to build a definitive 
--            leaderboard of products by revenue, handling ties gracefully.
-- -------------------------------------------------------------------
WITH ProductRevenueSummary AS (
    SELECT 
        od.ProductID, 
        p.ProductName, 
        SUM(od.Quantity * od.UnitPrice * (1 - od.Discount)) AS OrderAmountByProduct
    FROM dbo.[Order Details] od
    INNER JOIN dbo.Products p ON od.ProductID = p.ProductID 
    GROUP BY od.ProductID, p.ProductName
)
SELECT 
    ProductID,
    ProductName,
    OrderAmountByProduct, 
    RANK() OVER (ORDER BY OrderAmountByProduct DESC) AS [Rank], 
    DENSE_RANK() OVER (ORDER BY OrderAmountByProduct DESC) AS [Dense_Rank] 
FROM ProductRevenueSummary;


-- ===================================================================
-- SECTION 2: MARKETING & DISCOUNTS IMPACT
-- ===================================================================

-- -------------------------------------------------------------------
-- 2.1. Pricing Elasticity & Discount Volume Impact
-- Objective: Analyze if applying a discount (Remise) actually 
--            drives higher average product quantities per order line.
-- -------------------------------------------------------------------
WITH DiscountFlags AS (
    SELECT 
        od.*,
        CASE 
            WHEN Discount = 0 THEN 'No Discount'
            ELSE 'Discount Applied'
        END AS DiscountStatus
    FROM dbo.[Order Details] od
)
SELECT 
    df.DiscountStatus,
    AVG(CAST(df.Quantity AS FLOAT)) AS AvgQuantityPerOrderLine,
    MIN(df.Quantity) AS MinQtyOrdered,
    MAX(df.Quantity) AS MaxQtyOrdered,
    COUNT(*) AS TotalOrderLines
FROM DiscountFlags df
GROUP BY df.DiscountStatus;


-- ===================================================================
-- SECTION 3: MARKET BASKET ANALYSIS (PRODUCT CO-PURCHASING)
-- ===================================================================

-- -------------------------------------------------------------------
-- 3.1. Top Product Pairs Purchased Together
-- Objective: Identify hidden cross-selling opportunities by counting 
--            how often pairs of different products appear in the same OrderID.
-- Note: 'od1.ProductID < od2.ProductID' prevents duplicate pairing permutations.
-- -------------------------------------------------------------------
SELECT
    od1.ProductID AS Product_A,
    od2.ProductID AS Product_B,
    COUNT(*) AS TimesPurchasedTogether
FROM dbo.[Order Details] od1
INNER JOIN dbo.[Order Details] od2 ON od1.OrderID = od2.OrderID
  AND od1.ProductID < od2.ProductID
GROUP BY
    od1.ProductID,
    od2.ProductID
ORDER BY
    TimesPurchasedTogether DESC;