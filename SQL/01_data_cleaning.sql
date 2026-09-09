USE master;
GO

/*
======================================================================
PROJECT: Northwind Business Analysis
FILE: 01_data_cleaning.sql
DIALECT: SQL Server / T-SQL
DESCRIPTION: Non-destructive data quality audit and preparation checks
             for orders, order lines, dates, financial fields, and inventory.
METHODOLOGY STEP: [N] Data Quality Audit & Preparation

IMPORTANT:
- Legacy filename retained for repository continuity. This script is primarily a data-quality audit.
- This script audits data quality; it does not UPDATE or DELETE source data.
- Inventory fields are a current snapshot, not historical inventory observations.
======================================================================
*/


-- ===================================================================
-- SECTION 1: REFERENCE BASELINES
-- ===================================================================

-- -------------------------------------------------------------------
-- 1.1 Dataset coverage and active-customer baseline
-- -------------------------------------------------------------------
SELECT
    COUNT(*) AS TotalOrders,
    COUNT(DISTINCT CustomerID) AS ActiveCustomers,
    MIN(OrderDate) AS FirstOrderDate,
    MAX(OrderDate) AS LastOrderDate
FROM dbo.Orders;


-- -------------------------------------------------------------------
-- 1.2 Financial baseline using valid order-detail rows
-- Net Revenue = Quantity * UnitPrice * (1 - Discount)
-- Precision is preserved during calculation; ROUND is display-only.
-- -------------------------------------------------------------------
SELECT
    COUNT(*) AS ValidOrderLines,

    ROUND(
        SUM(
            CAST(Quantity AS DECIMAL(18,4))
            * CAST(UnitPrice AS DECIMAL(18,4))
        ),
        2
    ) AS GrossRevenue,

    ROUND(
        SUM(
            CAST(Quantity AS DECIMAL(18,4))
            * CAST(UnitPrice AS DECIMAL(18,4))
            * CAST(Discount AS DECIMAL(18,4))
        ),
        2
    ) AS DiscountAmount,

    ROUND(
        SUM(
            CAST(Quantity AS DECIMAL(18,4))
            * CAST(UnitPrice AS DECIMAL(18,4))
            * (1 - CAST(Discount AS DECIMAL(18,4)))
        ),
        2
    ) AS NetRevenue

FROM dbo.[Order Details]

WHERE Quantity > 0
  AND UnitPrice >= 0
  AND Discount BETWEEN 0 AND 1;


-- ===================================================================
-- SECTION 2: DATA QUALITY & INTEGRITY CHECKS
-- ===================================================================

-- -------------------------------------------------------------------
-- 2.1 Invalid financial/order-line values
-- Expected result for a clean dataset: zero rows.
-- -------------------------------------------------------------------
SELECT
    OrderID,
    ProductID,
    UnitPrice,
    Quantity,
    Discount,

    CASE
        WHEN Quantity IS NULL OR Quantity <= 0
            THEN 'Invalid Quantity'
        WHEN UnitPrice IS NULL OR UnitPrice < 0
            THEN 'Invalid Unit Price'
        WHEN Discount IS NULL OR Discount < 0 OR Discount > 1
            THEN 'Invalid Discount'
        ELSE 'Check'
    END AS DataQualityIssue

FROM dbo.[Order Details]

WHERE Quantity IS NULL
   OR Quantity <= 0
   OR UnitPrice IS NULL
   OR UnitPrice < 0
   OR Discount IS NULL
   OR Discount < 0
   OR Discount > 1;


-- -------------------------------------------------------------------
-- 2.2 Pending / unshipped orders
-- ShippedDate = NULL is treated as a business state, not automatically
-- as a data-quality error.
-- -------------------------------------------------------------------
SELECT
    OrderID,
    CustomerID,
    EmployeeID,
    OrderDate,
    RequiredDate,
    ShippedDate,
    Freight,
    'Unshipped / Pending' AS ShipmentState
FROM dbo.Orders
WHERE ShippedDate IS NULL
ORDER BY OrderDate, OrderID;


-- -------------------------------------------------------------------
-- 2.3 Temporal integrity checks
-- Expected result for a clean dataset: zero rows.
-- -------------------------------------------------------------------
SELECT
    OrderID,
    CustomerID,
    OrderDate,
    RequiredDate,
    ShippedDate,

    CASE
        WHEN ShippedDate IS NOT NULL
             AND ShippedDate < OrderDate
            THEN 'ShippedDate before OrderDate'

        WHEN RequiredDate IS NOT NULL
             AND RequiredDate < OrderDate
            THEN 'RequiredDate before OrderDate'

        ELSE 'Check'
    END AS TemporalIssue

FROM dbo.Orders

WHERE (ShippedDate IS NOT NULL AND ShippedDate < OrderDate)
   OR (RequiredDate IS NOT NULL AND RequiredDate < OrderDate)

ORDER BY OrderID;


-- -------------------------------------------------------------------
-- 2.4 Missing key operational references
-- These fields are important for customer, employee and shipper analysis.
-- -------------------------------------------------------------------
SELECT
    OrderID,
    CustomerID,
    EmployeeID,
    ShipVia,

    CASE
        WHEN CustomerID IS NULL THEN 'Missing CustomerID'
        WHEN EmployeeID IS NULL THEN 'Missing EmployeeID'
        WHEN ShipVia IS NULL THEN 'Missing ShipVia'
        ELSE 'Check'
    END AS MissingReferenceIssue

FROM dbo.Orders

WHERE CustomerID IS NULL
   OR EmployeeID IS NULL
   OR ShipVia IS NULL;


-- ===================================================================
-- SECTION 3: CURRENT INVENTORY HEALTH SNAPSHOT
-- ===================================================================

-- -------------------------------------------------------------------
-- 3.1 Inventory action mapping
--
-- IMPORTANT:
-- UnitsInStock / UnitsOnOrder / ReorderLevel are current snapshot fields.
-- They must not be used to claim that historical sales were caused by
-- historical stock-outs.
-- -------------------------------------------------------------------
SELECT
    ProductID,
    ProductName,
    UnitsInStock,
    UnitsOnOrder,
    ReorderLevel,
    Discontinued,

    UnitsInStock + UnitsOnOrder AS ProjectedStockPosition,

    CASE
        WHEN Discontinued = 1
            THEN 'No Action - Discontinued'

        WHEN UnitsInStock = 0
             AND UnitsOnOrder = 0
            THEN 'Urgent Reorder'

        WHEN UnitsInStock <= ReorderLevel
             AND UnitsOnOrder = 0
            THEN 'Reorder Needed'

        WHEN UnitsInStock <= ReorderLevel
             AND (UnitsInStock + UnitsOnOrder) <= ReorderLevel
            THEN 'Additional Reorder Needed'

        WHEN UnitsInStock <= ReorderLevel
             AND UnitsOnOrder > 0
            THEN 'Replenishment Pending'

        ELSE 'No Immediate Action'
    END AS InventoryAction

FROM dbo.Products

ORDER BY
    CASE
        WHEN Discontinued = 1 THEN 5
        WHEN UnitsInStock = 0 AND UnitsOnOrder = 0 THEN 1
        WHEN UnitsInStock <= ReorderLevel AND UnitsOnOrder = 0 THEN 2
        WHEN UnitsInStock <= ReorderLevel
             AND (UnitsInStock + UnitsOnOrder) <= ReorderLevel THEN 3
        WHEN UnitsInStock <= ReorderLevel AND UnitsOnOrder > 0 THEN 4
        ELSE 6
    END,
    ProductName;
