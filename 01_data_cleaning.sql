/*
======================================================================
PROJECT: Northwind Business Analysis
FILE: 01_data_cleaning.sql
DESCRIPTION: Data Quality Assurance, Handling Missing Values, and 
             Operational Constraints Verification.
METHODOLOGY STEP: [N] Netcleaning (Data Cleansing & Preparation)
======================================================================
*/

-- ===================================================================
-- SECTION 1: GLOBAL DATA AUDIT & BASELINES
-- ===================================================================

-- -------------------------------------------------------------------
-- 1.1. Unique Customer Audit
-- Objective: Establish the baseline count of unique active buyers.
-- -------------------------------------------------------------------
SELECT 
    COUNT(DISTINCT CustomerID) AS TotalUniqueCustomers
FROM dbo.Orders;


-- -------------------------------------------------------------------
-- 1.2. Baseline Gross Revenue Audit (Unfiltered)
-- Objective: Calculate absolute raw revenue from order lines for 
--            future variance testing.
-- -------------------------------------------------------------------
SELECT 
    SUM(Quantity * UnitPrice * (1 - Discount)) AS BaselineNetRevenue
FROM dbo.[Order Details];


-- ===================================================================
-- SECTION 2: HANDLING MISSING VALUES & ANOMALIES
-- ===================================================================

-- -------------------------------------------------------------------
-- 2.1. Backlog & Pending Shipments Analysis (NULL Handling)
-- Objective: Isolate active/pending orders from historical data.
--            In a production pipeline, this flags potential 
--            logistical bottlenecks.
-- -------------------------------------------------------------------
SELECT 
    OrderID,
    CustomerID,
    OrderDate,
    RequiredDate,
    Freight
FROM dbo.Orders
WHERE ShippedDate IS NULL;


-- -------------------------------------------------------------------
-- 2.2. Temporal Integrity Constraints Check
-- Objective: Detect logical anomalies where ShippedDate occurs 
--            before the actual OrderDate (data entry errors).
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
-- SECTION 3: OPERATIONAL & INVENTORY CONSTRAINTS
-- ===================================================================

-- -------------------------------------------------------------------
-- 3.1. Inventory Stock-Out & Reorder Level Alert
-- Objective: Identify products currently at risk of stock-out 
--            or requiring immediate supplier reordering.
-- Note: Filters out discontinued items to focus only on active products.
-- -------------------------------------------------------------------
SELECT 
    ProductID,
    ProductName,
    UnitsInStock,
    ReorderLevel,
    UnitsOnOrder
FROM dbo.Products
WHERE UnitsInStock <= ReorderLevel
  AND Discontinued = 0
ORDER BY UnitsInStock ASC;