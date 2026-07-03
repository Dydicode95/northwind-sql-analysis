/*
======================================================================
PROJECT: Northwind Business Analysis
FILE: 06_employee_analysis.sql
DESCRIPTION: Sales Force Performance Assessment and Revenue Contribution.
METHODOLOGY STEP: [A] Exploratory Analysis (Employee Performance)
======================================================================
*/

-- ===================================================================
-- SECTION 1: SALES FORCE LEADERBOARD
-- ===================================================================

-- -------------------------------------------------------------------
-- 1.1. Net Revenue Contribution & Efficiency by Sales Rep
-- -------------------------------------------------------------------
SELECT 
    e.EmployeeID,
    e.FirstName + ' ' + e.LastName AS SalesRep,
    e.Title AS EmployeeRole,
    COUNT(DISTINCT o.OrderID) AS TotalOrdersManaged,
    ROUND(SUM(od.Quantity * od.UnitPrice * (1 - CAST(od.Discount AS DECIMAL(10,4)))), 2) AS TotalRevenueGenerated,
    ROUND(SUM(od.Quantity * od.UnitPrice * (1 - CAST(od.Discount AS DECIMAL(10,4)))) / COUNT(DISTINCT o.OrderID), 2) AS AverageRevenuePerOrder
FROM dbo.Employees e 
INNER JOIN dbo.Orders o ON e.EmployeeID = o.EmployeeID 
INNER JOIN dbo.[Order Details] od ON o.OrderID = od.OrderID
GROUP BY 
    e.EmployeeID,
    e.FirstName + ' ' + e.LastName,
    e.Title
ORDER BY TotalRevenueGenerated DESC;

-- -------------------------------------------------------------------
-- 1.2. Top Performer Revenue Contribution (Cross Join for 18.40% KPI)
-- -------------------------------------------------------------------
WITH RepRevenue AS (
    SELECT 
        e.EmployeeID,
        e.FirstName + ' ' + e.LastName AS SalesRep,
        SUM(od.Quantity * od.UnitPrice * (1 - CAST(od.Discount AS DECIMAL(10,4)))) AS RepTotalNet
    FROM dbo.Employees e 
    INNER JOIN dbo.Orders o ON e.EmployeeID = o.EmployeeID 
    INNER JOIN dbo.[Order Details] od ON o.OrderID = od.OrderID
    GROUP BY 
        e.EmployeeID, 
        e.FirstName + ' ' + e.LastName
),
CompanyRevenue AS (
    SELECT SUM(RepTotalNet) AS GlobalCompanyRevenue 
    FROM RepRevenue
)
SELECT TOP 1
    r.SalesRep,
    ROUND(r.RepTotalNet, 2) AS TopPerformerRevenue,
    ROUND(c.GlobalCompanyRevenue, 2) AS GlobalCompanyRevenue,
    ROUND((r.RepTotalNet / c.GlobalCompanyRevenue) * 100, 2) AS ContributionPercentage
FROM RepRevenue r
CROSS JOIN CompanyRevenue c
ORDER BY r.RepTotalNet DESC;

-- -------------------------------------------------------------------
-- 1.3. Employee Geographic Footprint (Customer Origin)
-- -------------------------------------------------------------------
SELECT 
    e.FirstName + ' ' + e.LastName AS SalesRep,
    c.Country AS ClientCountry,
    COUNT(DISTINCT o.OrderID) AS TotalOrders,
    ROUND(SUM(od.Quantity * od.UnitPrice * (1 - CAST(od.Discount AS DECIMAL(10,4)))), 2) AS RevenueGenerated
FROM dbo.Employees e
INNER JOIN dbo.Orders o ON e.EmployeeID = o.EmployeeID
INNER JOIN dbo.Customers c ON o.CustomerID = c.CustomerID
INNER JOIN dbo.[Order Details] od ON o.OrderID = od.OrderID
GROUP BY 
    e.FirstName + ' ' + e.LastName,
    c.Country
ORDER BY 
    SalesRep, 
    RevenueGenerated DESC;