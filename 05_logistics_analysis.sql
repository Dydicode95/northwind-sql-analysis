{\rtf1\ansi\ansicpg1252\cocoartf2870
\cocoatextscaling0\cocoaplatform0{\fonttbl\f0\fswiss\fcharset0 Helvetica;}
{\colortbl;\red255\green255\blue255;}
{\*\expandedcolortbl;;}
\paperw11900\paperh16840\margl1440\margr1440\vieww11520\viewh8400\viewkind0
\pard\tx720\tx1440\tx2160\tx2880\tx3600\tx4320\tx5040\tx5760\tx6480\tx7200\tx7920\tx8640\pardirnatural\partightenfactor0

\f0\fs24 \cf0 -- =========================================================================================\
-- FILE: 05_logistics_analysis.sql\
-- PURPOSE: Exploratory Analysis of Operations & Logistics\
-- AUTHOR: Data Analyst (Northwind Project)\
-- DESCRIPTION: Evaluates shipping partners, regional supply chain bottlenecks, \
--              freight costs, and late shipment rates.\
-- =========================================================================================\
\
USE Northwind;\
GO\
\
-- -----------------------------------------------------------------------------------------\
-- QUERY 1: CARRIER BENCHMARKING (SPEED & RELIABILITY)\
-- Business Objective: Evaluate which shipper is the most reliable and cost-effective.\
-- -----------------------------------------------------------------------------------------\
SELECT \
    s.CompanyName AS ShipperName,\
    COUNT(o.OrderID) AS TotalShipments,\
    -- Average delay in days\
    ROUND(AVG(CAST(DATEDIFF(DAY, o.OrderDate, o.ShippedDate) AS FLOAT)), 2) AS AvgShippingDelayDays,\
    -- Average cost per shipment\
    ROUND(AVG(o.Freight), 2) AS AvgFreightCost,\
    -- Total Late Shipments\
    SUM(CASE WHEN o.ShippedDate > o.RequiredDate THEN 1 ELSE 0 END) AS LateShipments,\
    -- Late Shipment Rate (%)\
    ROUND(CAST(SUM(CASE WHEN o.ShippedDate > o.RequiredDate THEN 1 ELSE 0 END) AS FLOAT) / COUNT(o.OrderID) * 100, 2) AS LateShipmentRate\
FROM dbo.Orders o\
INNER JOIN dbo.Shippers s ON o.ShipVia = s.ShipperID\
-- Data Cleaning: Exclude unshipped orders and temporal anomalies\
WHERE o.ShippedDate IS NOT NULL \
  AND o.ShippedDate >= o.OrderDate\
GROUP BY s.CompanyName\
ORDER BY AvgShippingDelayDays ASC;\
\
\
-- -----------------------------------------------------------------------------------------\
-- QUERY 2: DESTINATION BOTTLENECKS (REGIONAL SUPPLY CHAIN)\
-- Business Objective: Identify which countries suffer from the worst shipping delays.\
-- -----------------------------------------------------------------------------------------\
SELECT \
    o.ShipCountry,\
    COUNT(o.OrderID) AS TotalShipments,\
    SUM(o.Freight) AS TotalFreightCosts,\
    ROUND(AVG(o.Freight), 2) AS AvgFreightCost,\
    ROUND(AVG(CAST(DATEDIFF(DAY, o.OrderDate, o.ShippedDate) AS FLOAT)), 2) AS AvgShippingDelayDays,\
    ROUND(CAST(SUM(CASE WHEN o.ShippedDate > o.RequiredDate THEN 1 ELSE 0 END) AS FLOAT) / COUNT(o.OrderID) * 100, 2) AS LateShipmentRate\
FROM dbo.Orders o\
WHERE o.ShippedDate IS NOT NULL \
  AND o.ShippedDate >= o.OrderDate\
GROUP BY o.ShipCountry\
-- Sort by worst delay to highlight bottlenecks\
ORDER BY AvgShippingDelayDays DESC;\
\
\
-- -----------------------------------------------------------------------------------------\
-- QUERY 3: LOGISTICS SEASONALITY & TRENDS\
-- Business Objective: Track average shipping delays over time to spot operational crises.\
-- -----------------------------------------------------------------------------------------\
SELECT \
    YEAR(o.OrderDate) AS OrderYear,\
    MONTH(o.OrderDate) AS OrderMonth,\
    s.CompanyName AS ShipperName,\
    COUNT(o.OrderID) AS TotalShipments,\
    ROUND(AVG(CAST(DATEDIFF(DAY, o.OrderDate, o.ShippedDate) AS FLOAT)), 2) AS AvgShippingDelayDays\
FROM dbo.Orders o\
INNER JOIN dbo.Shippers s ON o.ShipVia = s.ShipperID\
WHERE o.ShippedDate IS NOT NULL \
  AND o.ShippedDate >= o.OrderDate\
GROUP BY \
    YEAR(o.OrderDate), \
    MONTH(o.OrderDate), \
    s.CompanyName\
ORDER BY \
    OrderYear ASC, \
    OrderMonth ASC, \
    ShipperName ASC;\
\
\
-- -----------------------------------------------------------------------------------------\
-- QUERY 4: FREIGHT COST TO REVENUE RATIO (PROFITABILITY IMPACT)\
-- Business Objective: Understand how freight costs impact the net revenue per order.\
-- -----------------------------------------------------------------------------------------\
WITH OrderRevenue AS (\
    SELECT \
        OrderID,\
        SUM(Quantity * UnitPrice * (1 - CAST(Discount AS DECIMAL(10,4)))) AS NetRevenue\
    FROM dbo.[Order Details]\
    GROUP BY OrderID\
)\
SELECT \
    o.ShipCountry,\
    COUNT(o.OrderID) AS TotalOrders,\
    ROUND(SUM(r.NetRevenue), 2) AS TotalNetRevenue,\
    ROUND(SUM(o.Freight), 2) AS TotalFreightCosts,\
    -- Metric: Freight as a percentage of Revenue (Margin impact)\
    ROUND((SUM(o.Freight) / SUM(r.NetRevenue)) * 100, 2) AS FreightToRevenueRatio\
FROM dbo.Orders o\
INNER JOIN OrderRevenue r ON o.OrderID = r.OrderID\
WHERE o.ShippedDate IS NOT NULL\
GROUP BY o.ShipCountry\
ORDER BY FreightToRevenueRatio DESC;}