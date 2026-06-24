/*
======================================================================
PROJECT: Northwind Business Analysis
FILE: 03_customer_analysis.sql
DESCRIPTION: Customer Value Segmentation, RFM Modeling, Inactivity 
             Tracking (Churn Risk), and Regional Basket Benchmarking.
METHODOLOGY STEP: [A] Exploratory Analysis (Customer Activity)
======================================================================
*/

-- ===================================================================
-- SECTION 1: CUSTOMER REVENUE CONTRIBUTION & SEGMENTATION
-- ===================================================================

-- -------------------------------------------------------------------
-- 1.1. Top 10 High-Value Customers
-- Objective: Identify the clients contributing the most to absolute 
--            net revenue (Pareto baseline).
-- -------------------------------------------------------------------
SELECT TOP 10 
    so.CustomerID, 
    SUM(od2.Quantity * (od2.UnitPrice * (1 - od2.Discount))) AS TotalRevenue
FROM dbo.Orders so 
INNER JOIN dbo.[Order Details] od2 ON so.OrderID = od2.OrderID 
GROUP BY so.CustomerID
ORDER BY TotalRevenue DESC;


-- -------------------------------------------------------------------
-- 1.2. Advanced RFM Segmentation Model
-- Objective: Classify the entire customer database into marketing personas 
--            based on Recency, Frequency, and Monetary Value quartiles.
-- -------------------------------------------------------------------
WITH OrderCosts AS (
    SELECT 
        OrderID,
        SUM(Quantity * UnitPrice * (1 - Discount)) AS NetOrderAmount
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
    INNER JOIN OrderCosts oc ON o.OrderID = oc.OrderID
    GROUP BY o.CustomerID
),
RecencyCalculated AS (
    SELECT 
        *,
        DATEDIFF(DAY, LastOrderDate, (SELECT MAX(OrderDate) FROM dbo.Orders)) AS RecencyDays
    FROM CustomerMetrics
),
RFM_Scores AS (
    SELECT 
        *,
        NTILE(4) OVER (ORDER BY RecencyDays ASC) AS R_Score,  -- Score 4 = Recently purchased
        NTILE(4) OVER (ORDER BY Frequency ASC) AS F_Score,    -- Score 4 = Purchases very frequently
        NTILE(4) OVER (ORDER BY MonetaryValue ASC) AS M_Score -- Score 4 = High Spender
    FROM RecencyCalculated
)
SELECT 
    CustomerID,
    RecencyDays,
    Frequency,
    MonetaryValue,
    R_Score,
    F_Score,
    M_Score,
    (R_Score + F_Score + M_Score) AS Total_RFM_Score,
    CASE
        WHEN R_Score >= 3 AND F_Score >= 3 AND M_Score >= 3 THEN 'Champions / VIP'
        WHEN R_Score <= 2 AND F_Score >= 3 AND M_Score >= 3 THEN 'At Risk / Can''t Lose Them'
        WHEN R_Score >= 3 AND F_Score <= 2 AND M_Score <= 2 THEN 'New / Occasional Customers'
        WHEN R_Score <= 1 AND F_Score <= 1 AND M_Score <= 1 THEN 'Lost / Low Value'
        ELSE 'Regular Customers'
    END AS Customer_Segment
FROM RFM_Scores
ORDER BY MonetaryValue DESC;


-- ===================================================================
-- SECTION 2: CHURN RISK & BEHAVIORAL BENCHMARKING
-- ===================================================================

-- -------------------------------------------------------------------
-- 2.1. Inactive Customers (90+ Days Churn Alert)
-- Objective: Generate an operational list of customers who have not 
--            placed an order in the last 90 days of active data.
-- -------------------------------------------------------------------
WITH LastCustomerOrder AS (
    SELECT 
        CustomerID, 
        MAX(OrderDate) AS LastOrder
    FROM dbo.Orders
    GROUP BY CustomerID
),
MaxDatabaseDate AS (
    SELECT 
        MAX(OrderDate) AS MaxOrderDate
    FROM dbo.Orders
)
SELECT 
    lco.CustomerID,
    lco.LastOrder,
    DATEDIFF(DAY, lco.LastOrder, mdd.MaxOrderDate) AS DaysOfInactivity
FROM LastCustomerOrder lco
CROSS JOIN MaxDatabaseDate mdd
WHERE DATEDIFF(DAY, lco.LastOrder, mdd.MaxOrderDate) > 90
ORDER BY DaysOfInactivity DESC;


-- -------------------------------------------------------------------
-- 2.2. Regional Basket Variance Analysis
-- Objective: Compare each individual customer's average order value 
--            against their specific country's baseline benchmark.
-- -------------------------------------------------------------------
WITH CustomerBaskets AS (
    SELECT
        o.CustomerID,
        o.ShipCountry,
        SUM(od.Quantity * od.UnitPrice * (1 - od.Discount)) / COUNT(DISTINCT o.OrderID) AS AverageBasketPerCustomer
    FROM dbo.Orders o 
    INNER JOIN dbo.[Order Details] od ON o.OrderID = od.OrderID 
    GROUP BY o.CustomerID, o.ShipCountry
),
CountryBaskets AS (
    SELECT
        o.ShipCountry,
        SUM(od.Quantity * od.UnitPrice * (1 - od.Discount)) / COUNT(DISTINCT o.OrderID) AS AverageBasketPerCountry
    FROM dbo.Orders o
    INNER JOIN dbo.[Order Details] od ON o.OrderID = od.OrderID
    GROUP BY o.ShipCountry
)
SELECT
    cb.CustomerID,
    cb.ShipCountry,
    cb.AverageBasketPerCustomer,
    ctb.AverageBasketPerCountry,
    (cb.AverageBasketPerCustomer - ctb.AverageBasketPerCountry) AS VarianceFromCountryAverage
FROM CountryBaskets ctb
INNER JOIN CustomerBaskets cb ON ctb.ShipCountry = cb.ShipCountry
ORDER BY cb.ShipCountry, cb.AverageBasketPerCustomer DESC;