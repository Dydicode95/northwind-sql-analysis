/*
======================================================================
PROJECT: Northwind Business Analysis
FILE: 01_data_cleaning.sql
DESCRIPTION: Data Quality Assurance, Handling Missing Values, 
             Anomalies Filtering, and Inventory Health Mapping.
METHODOLOGY STEP: [N] Netcleaning (Data Cleansing & Preparation)
======================================================================
*/

-- ===================================================================
-- SECTION 1: DATA AUDIT & GOLD BASES (Establishing Truth)
-- ===================================================================

-- -------------------------------------------------------------------
-- 1.1. Reference Unique Customer Count
-- -------------------------------------------------------------------
SELECT 
    COUNT(DISTINCT CustomerID) AS TotalUniqueCustomers
FROM dbo.Orders;

-- -------------------------------------------------------------------
-- 1.2. Financial Baseline & Precision Cleansing
-- -------------------------------------------------------------------
SELECT 
    ROUND(SUM(Quantity * UnitPrice * (1 - CAST(Discount AS DECIMAL(10,4)))), 2) AS CleanedBaselineNetRevenue
FROM dbo.[Order Details]
WHERE Quantity > 0 AND UnitPrice >= 0; 

-- ===================================================================
-- SECTION 2: ANOMALY ISOLATION & HANDLING MISSING VALUES
-- ===================================================================

-- -------------------------------------------------------------------
-- 2.1. Handling Missing Values (Pending Shipments)
-- -------------------------------------------------------------------
SELECT 
    OrderID,
    CustomerID,
    OrderDate,
    RequiredDate,
    Freight,
    ISNULL(CONVERT(VARCHAR, ShippedDate), 'Unshipped/Backlog') AS ShippedStatus
FROM dbo.Orders
WHERE ShippedDate IS NULL;

-- -------------------------------------------------------------------
-- 2.2. Temporal Integrity Constraints Check
-- -------------------------------------------------------------------
SELECT 
    OrderID,
    CustomerID,
    OrderDate,
    ShippedDate,
    DATEDIFF(DAY, OrderDate, ShippedDate) AS AnomalousNegativeDays
FROM dbo.Orders
WHERE ShippedDate < OrderDate; 

-- ===================================================================
-- SECTION 3: OPERATIONAL CRITICAL FILTERS (Supply Chain)
-- ===================================================================

-- -------------------------------------------------------------------
-- 3.1. Inventory Stock-Out & Reorder Alerting
-- -------------------------------------------------------------------
SELECT 
    ProductID,
    ProductName,
    UnitsInStock,
    UnitsOnOrder,
    ReorderLevel,
    (UnitsInStock + UnitsOnOrder) AS TotalStockPosition,
    CASE 
        WHEN (UnitsInStock + UnitsOnOrder) <= ReorderLevel THEN 'CRITICAL: Reorder Immediately'
        ELSE 'Safe'
    END AS OperationalAction
FROM dbo.Products
WHERE Discontinued = 0
  AND (UnitsInStock + UnitsOnOrder) <= ReorderLevel
ORDER BY TotalStockPosition ASC;