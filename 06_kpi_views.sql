/*
======================================================================
PROJECT: Northwind Business Analysis
FILE: 06_kpi_views.sql
DESCRIPTION: Creating Database Views to streamline data injection 
             into Looker Studio (BI Semantic Layer).
METHODOLOGY STEP: [D] Decision (Dashboarding Preparation)
======================================================================
*/

-- -------------------------------------------------------------------
-- VIEW 1: Shipping & Logistical Performance View
-- Objective: Provides Looker Studio with a ready-made table containing
--            shipping delays cross-referenced with carrier names.
-- -------------------------------------------------------------------

-- Bloc 1 : Création de la vue Logistique
CREATE OR ALTER VIEW dbo.v_bi_shipping_performance AS
SELECT 
    o.ShipCountry,
    s.CompanyName AS ShipperName,
    AVG(DATEDIFF(DAY, o.OrderDate, o.ShippedDate)) AS AvgShippingDelayDays, 
    COUNT(o.OrderID) AS TotalOrdersShipped
FROM dbo.Orders o
INNER JOIN dbo.Shippers s ON o.ShipVia = s.ShipperID
WHERE o.ShippedDate IS NOT NULL          
  AND o.ShippedDate >= o.OrderDate         
GROUP BY o.ShipCountry, s.CompanyName;


-- -------------------------------------------------------------------
-- VIEW 2: Global Sales & Turnover by Country
-- Objective: Allows Looker Studio to instantly generate geographic maps
--            and regional sales leaderboards.
-- -------------------------------------------------------------------

CREATE OR ALTER VIEW dbo.v_bi_regional_turnover AS
SELECT 
    o.ShipCountry,
    COUNT(DISTINCT o.OrderID) AS NumberOfOrders,
    AVG(od.Quantity * od.UnitPrice * (1 - od.Discount)) AS AverageOrderValue, 
    SUM(od.Quantity * od.UnitPrice * (1 - od.Discount)) AS TotalTurnover 
FROM dbo.Orders o 
INNER JOIN dbo.[Order Details] od ON o.OrderID = od.OrderID 
GROUP BY o.ShipCountry;


-- -------------------------------------------------------------------
-- VIEW 3: Order Size Classification (IQR Method)
-- Objective: Feed the dashboard with classified order sizes (Small, Medium, Big)
--            for advanced behavioral filtering.
-- -------------------------------------------------------------------

CREATE OR ALTER VIEW dbo.v_bi_order_classification AS
WITH OrderAmounts AS (
    SELECT
        od.OrderID,
        SUM(od.Quantity * od.UnitPrice * (1 - od.Discount)) AS OrderAmount
    FROM dbo.[Order Details] od
    GROUP BY od.OrderID
),
Quartiles AS (
    SELECT
        OrderID,
        OrderAmount,
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY OrderAmount) OVER () AS Q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY OrderAmount) OVER () AS Q3
    FROM OrderAmounts
),
Classification AS (
    SELECT
        OrderID,
        OrderAmount,
        Q1,
        Q3,
        Q3 - Q1 AS IQR
    FROM Quartiles
)
SELECT
    OrderID,
    OrderAmount,
    CASE
        WHEN OrderAmount < Q1 - 1.5 * IQR THEN 'Small Order'
        WHEN OrderAmount > Q3 + 1.5 * IQR THEN 'Large Order'
        ELSE 'Medium Order'
    END AS Order_Size_Category
FROM Classification;