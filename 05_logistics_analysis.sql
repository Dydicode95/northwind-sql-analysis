/*
======================================================================
PROJECT: Northwind Business Analysis
FILE: 05_logistics_analysis.sql
DESCRIPTION: Evaluates shipping partners, regional supply chain bottlenecks, 
             freight costs, and late shipment rates.
METHODOLOGY STEP: [A] Exploratory Analysis (Operations & Logistics)
======================================================================
*/

-- ===================================================================
-- SECTION 1: CARRIER BENCHMARKING (SPEED & RELIABILITY)
-- ===================================================================

SELECT 
    s.CompanyName AS ShipperName,
    COUNT(o.OrderID) AS TotalShipments,
    ROUND(AVG(CAST(DATEDIFF(DAY, o.OrderDate, o.ShippedDate) AS FLOAT)), 2) AS AvgShippingDelayDays,
    ROUND(AVG(o.Freight), 2) AS AvgFreightCost,
    SUM(CASE WHEN o.ShippedDate > o.RequiredDate THEN 1 ELSE 0 END) AS LateShipments,
    ROUND(CAST(SUM(CASE WHEN o.ShippedDate > o.RequiredDate THEN 1 ELSE 0 END) AS FLOAT) / COUNT(o.OrderID) * 100, 2) AS LateShipmentRate
FROM dbo.Orders o
INNER JOIN dbo.Shippers s ON o.ShipVia = s.ShipperID
WHERE o.ShippedDate IS NOT NULL 
  AND o.ShippedDate >= o.OrderDate
GROUP BY s.CompanyName
ORDER BY AvgShippingDelayDays ASC;

-- ===================================================================
-- SECTION 2: DESTINATION BOTTLENECKS (REGIONAL SUPPLY CHAIN)
-- ===================================================================

SELECT 
    o.ShipCountry,
    COUNT(o.OrderID) AS TotalShipments,
    SUM(o.Freight) AS TotalFreightCosts,
    ROUND(AVG(o.Freight), 2) AS AvgFreightCost,
    ROUND(AVG(CAST(DATEDIFF(DAY, o.OrderDate, o.ShippedDate) AS FLOAT)), 2) AS AvgShippingDelayDays,
    ROUND(CAST(SUM(CASE WHEN o.ShippedDate > o.RequiredDate THEN 1 ELSE 0 END) AS FLOAT) / COUNT(o.OrderID) * 100, 2) AS LateShipmentRate
FROM dbo.Orders o
WHERE o.ShippedDate IS NOT NULL 
  AND o.ShippedDate >= o.OrderDate
GROUP BY o.ShipCountry
ORDER BY AvgShippingDelayDays DESC;

-- ===================================================================
-- SECTION 3: LOGISTICS SEASONALITY & TRENDS
-- ===================================================================

SELECT 
    YEAR(o.OrderDate) AS OrderYear,
    MONTH(o.OrderDate) AS OrderMonth,
    s.CompanyName AS ShipperName,
    COUNT(o.OrderID) AS TotalShipments,
    ROUND(AVG(CAST(DATEDIFF(DAY, o.OrderDate, o.ShippedDate) AS FLOAT)), 2) AS AvgShippingDelayDays
FROM dbo.Orders o
INNER JOIN dbo.Shippers s ON o.ShipVia = s.ShipperID
WHERE o.ShippedDate IS NOT NULL 
  AND o.ShippedDate >= o.OrderDate
GROUP BY 
    YEAR(o.OrderDate), 
    MONTH(o.OrderDate), 
    s.CompanyName
ORDER BY 
    OrderYear ASC, 
    OrderMonth ASC, 
    ShipperName ASC;

-- ===================================================================
-- SECTION 4: FREIGHT COST TO REVENUE RATIO (PROFITABILITY IMPACT)
-- ===================================================================

WITH OrderRevenue AS (
    SELECT 
        OrderID,
        SUM(Quantity * UnitPrice * (1 - CAST(Discount AS DECIMAL(10,4)))) AS NetRevenue
    FROM dbo.[Order Details]
    GROUP BY OrderID
)
SELECT 
    o.ShipCountry,
    COUNT(o.OrderID) AS TotalOrders,
    ROUND(SUM(r.NetRevenue), 2) AS TotalNetRevenue,
    ROUND(SUM(o.Freight), 2) AS TotalFreightCosts,
    ROUND((SUM(o.Freight) / SUM(r.NetRevenue)) * 100, 2) AS FreightToRevenueRatio
FROM dbo.Orders o
INNER JOIN OrderRevenue r ON o.OrderID = r.OrderID
WHERE o.ShippedDate IS NOT NULL
GROUP BY o.ShipCountry
ORDER BY FreightToRevenueRatio DESC;