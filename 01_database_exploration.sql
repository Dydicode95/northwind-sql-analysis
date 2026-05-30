/*
=========================================================
File: 01_database_exploration.sql
Project: Northwind SQL Business Analysis
Description:
Database exploration and initial data quality checks.
=========================================================
*/

-- =====================================================
-- 1. Explore database structure
-- Purpose: identify available business tables
-- =====================================================

SELECT *
FROM INFORMATION_SCHEMA.TABLES;


-- =====================================================
-- 2. Explore columns in key business tables
-- Purpose: understand available variables for analysis
-- =====================================================

SELECT
    TABLE_NAME,
    COLUMN_NAME,
    DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME IN (
    'Customers',
    'Orders',
    'Products',
    'Categories'
)
ORDER BY TABLE_NAME;


-- =====================================================
-- 3. Count records in core tables
-- Purpose: understand dataset size
-- =====================================================

SELECT COUNT(*) AS total_customers
FROM Customers;

SELECT COUNT(*) AS total_orders
FROM Orders;

SELECT COUNT(*) AS total_products
FROM Products;


-- =====================================================
-- 4. Preview business tables
-- Purpose: inspect raw data structure
-- =====================================================

SELECT TOP 10 *
FROM Customers;

SELECT TOP 10 *
FROM Orders;


-- =====================================================
-- 5. Check order date range
-- Purpose: identify analysis timeframe
-- =====================================================

SELECT
    MIN(OrderDate) AS first_order_date,
    MAX(OrderDate) AS last_order_date
FROM Orders;