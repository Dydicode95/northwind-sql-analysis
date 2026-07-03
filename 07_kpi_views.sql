-- =========================================================================================
-- FILE: 07_kpi_views.sql
-- PURPOSE: Generate the final Business Intelligence Data Marts for Looker Studio ingestion.
-- AUTHOR: Data Analyst (Northwind Project)
-- =========================================================================================

-- -----------------------------------------------------------------------------------------
-- VIEW 1: REGIONAL TURNOVER & MACRO SALES
-- Business Objective: Macro revenue trends, discounts impact, and Average Order Value (AOV)
-- -----------------------------------------------------------------------------------------
GO
CREATE OR ALTER VIEW dbo.v_bi_regional_turnover_update AS
SELECT 
    o.ShipCountry,
    COUNT(DISTINCT o.OrderID) AS NumberOfOrders,
    -- 1. Le CA Brut (Si on avait tout vendu plein pot)
    ROUND(SUM(od.Quantity * od.UnitPrice), 2) AS GrossTurnover,
    -- 2. Le CA Net (L'argent qui rentre vraiment dans les caisses)
    ROUND(SUM(od.Quantity * od.UnitPrice * (1 - CAST(od.Discount AS DECIMAL(10,4)))), 2) AS NetTurnover, 
    -- 3. L'impact financier des remises (L'argent "sacrifié")
    ROUND(SUM(od.Quantity * od.UnitPrice * CAST(od.Discount AS DECIMAL(10,4))), 2) AS TotalDiscountAmount,
    -- 4. Le Panier Moyen Réel (Basé sur le CA Net)
    ROUND(SUM(od.Quantity * od.UnitPrice * (1 - CAST(od.Discount AS DECIMAL(10,4)))) / COUNT(DISTINCT o.OrderID), 2) AS AverageOrderValue 
FROM dbo.Orders o 
INNER JOIN dbo.[Order Details] od ON o.OrderID = od.OrderID 
GROUP BY o.ShipCountry;


-- -----------------------------------------------------------------------------------------
-- VIEW 2: ORDER CLASSIFICATION (STATISTICAL OUTLIERS)
-- Business Objective: Categorize order sizes (Small, Medium, Large) using IQR methodology
-- -----------------------------------------------------------------------------------------
GO
CREATE OR ALTER VIEW dbo.v_bi_order_classification AS
WITH OrderAmounts AS (
    SELECT
        o.ShipCountry,
        od.OrderID,
        ROUND(SUM(od.Quantity * od.UnitPrice * (1 - CAST(od.Discount AS DECIMAL(10,4)))), 2) AS OrderAmount
    FROM dbo.[Order Details] od
    INNER JOIN dbo.Orders o ON od.OrderID = o.OrderID 
    GROUP BY 
        o.ShipCountry, 
        od.OrderID
),
Quartiles AS (
    SELECT
        ShipCountry,
        OrderID,
        OrderAmount,
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY OrderAmount) OVER () AS Q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY OrderAmount) OVER () AS Q3
    FROM OrderAmounts
),
Classification AS (
    SELECT
        ShipCountry,
        OrderID,
        OrderAmount,
        Q1,
        Q3,
        Q3 - Q1 AS IQR
    FROM Quartiles
)
SELECT
    ShipCountry,
    OrderID,
    OrderAmount,
    CASE
        WHEN OrderAmount < (Q1 - 1.5 * IQR) THEN 'Small Order'
        WHEN OrderAmount > (Q3 + 1.5 * IQR) THEN 'Large Order'
        ELSE 'Medium Order'
    END AS Order_Size_Category
FROM Classification;


-- -----------------------------------------------------------------------------------------
-- VIEW 3: PRODUCT PERFORMANCE BY REGION & MONTH
-- Business Objective: Track product revenue, volumes, seasonality, and rankings
-- -----------------------------------------------------------------------------------------
GO
CREATE OR ALTER VIEW dbo.v_bi_product_performance_by_region AS
SELECT 
    o.ShipCountry,
    -- Création d'une date propre bloquée au 1er du mois (ex: 1997-07-01)
    DATEFROMPARTS(YEAR(o.OrderDate), MONTH(o.OrderDate), 1) AS OrderMonth,
    p.ProductID, 
    p.ProductName, 
    c.CategoryName,
    SUM(od.Quantity) AS TotalQuantitySold,
    ROUND(SUM(od.Quantity * od.UnitPrice * (1 - CAST(od.Discount AS DECIMAL(10,4)))), 2) AS TotalRevenue,
    -- Le classement se fait par Pays ET par Mois
    RANK() OVER (
        PARTITION BY o.ShipCountry, DATEFROMPARTS(YEAR(o.OrderDate), MONTH(o.OrderDate), 1)
        ORDER BY SUM(od.Quantity * od.UnitPrice * (1 - CAST(od.Discount AS DECIMAL(10,4)))) DESC
    ) AS RegionalMonthlyRank
FROM dbo.[Order Details] od
INNER JOIN dbo.Orders o ON od.OrderID = o.OrderID
INNER JOIN dbo.Products p ON od.ProductID = p.ProductID 
INNER JOIN dbo.Categories c ON p.CategoryID = c.CategoryID
GROUP BY 
    o.ShipCountry,
    DATEFROMPARTS(YEAR(o.OrderDate), MONTH(o.OrderDate), 1),
    p.ProductID, 
    p.ProductName, 
    c.CategoryName;


-- -----------------------------------------------------------------------------------------
-- VIEW 4: SHIPPING & LOGISTICS PERFORMANCE
-- Business Objective: Track shipping times, identify delays, and evaluate carrier costs
-- -----------------------------------------------------------------------------------------
GO
CREATE OR ALTER VIEW dbo.v_bi_shipping_performance AS
SELECT 
    o.OrderID,
    o.ShipCountry,
    s.CompanyName AS ShipperName,
    -- Ajout du mois pour pouvoir suivre si les retards augmentent en fin d'année
    CONVERT(varchar(6), o.OrderDate, 112) AS OrderMonth,
    -- Vitesse d'expédition exacte pour cette commande spécifique
    DATEDIFF(DAY, o.OrderDate, o.ShippedDate) AS ShippingDelayDays, 
    -- La dimension de Statut pour suivre la qualité de service
    CASE 
        WHEN o.ShippedDate > o.RequiredDate THEN 'Late Delivery'
        ELSE 'On Time Delivery'
    END AS ShippingStatus,
    -- Coût exact de cette expédition
    o.Freight AS FreightCost
FROM dbo.Orders o
INNER JOIN dbo.Shippers s ON o.ShipVia = s.ShipperID
-- Filtre de nettoyage des anomalies logistiques
WHERE o.ShippedDate IS NOT NULL          
  AND o.ShippedDate >= o.OrderDate;


-- -----------------------------------------------------------------------------------------
-- VIEW 5: CUSTOMER 360 & RFM SEGMENTATION
-- Business Objective: Identify VIP clients and monitor Churn risk using Recency/Frequency
-- -----------------------------------------------------------------------------------------
GO
CREATE OR ALTER VIEW dbo.v_bi_customer_360 AS
WITH OrderCosts AS (
    SELECT 
        OrderID,
        -- Sécurisation du calcul financier
        SUM(Quantity * UnitPrice * (1 - CAST(Discount AS DECIMAL(10,4)))) AS NetOrderAmount
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
        CustomerID,
        LastOrderDate,
        Frequency,
        MonetaryValue,
        -- Calcul des jours d'inactivité (Sert pour la récence ET le risque de Churn)
        DATEDIFF(DAY, LastOrderDate, (SELECT MAX(OrderDate) FROM dbo.Orders)) AS RecencyDays 
    FROM CustomerMetrics
),
RFM_Scores AS (
    SELECT 
        *,
        -- Tri corrigé (DESC pour la Récence pour que les inactifs aient un petit score)
        NTILE(4) OVER (ORDER BY RecencyDays DESC) AS R_Score,  
        NTILE(4) OVER (ORDER BY Frequency ASC) AS F_Score,    
        NTILE(4) OVER (ORDER BY MonetaryValue ASC) AS M_Score 
    FROM RecencyCalculated
)
SELECT 
    r.CustomerID,
    c.CompanyName,
    c.Country,
    r.LastOrderDate,
    r.RecencyDays AS DaysOfInactivity,
    r.Frequency AS TotalOrders,
    ROUND(r.MonetaryValue, 2) AS TotalSpent,
    r.R_Score,
    r.F_Score,
    r.M_Score,
    (r.R_Score + r.F_Score + r.M_Score) AS Total_RFM_Score,
    CASE
        WHEN r.R_Score >= 3 AND r.F_Score >= 3 AND r.M_Score >= 3 THEN 'Champions / VIP'
        WHEN r.R_Score <= 2 AND r.F_Score >= 3 AND r.M_Score >= 3 THEN 'At Risk / Can''t Lose Them'
        WHEN r.R_Score >= 3 AND r.F_Score <= 2 AND r.M_Score <= 2 THEN 'New / Occasional Customers'
        WHEN r.R_Score <= 1 AND r.F_Score <= 1 AND r.M_Score <= 1 THEN 'Lost / Low Value'
        ELSE 'Regular Customers'
    END AS Customer_Segment
FROM RFM_Scores r
INNER JOIN dbo.Customers c ON r.CustomerID = c.CustomerID;


-- -----------------------------------------------------------------------------------------
-- VIEW 6: EMPLOYEE SALES PERFORMANCE
-- Business Objective: Assess sales force efficiency, order volumes, and average revenue
-- -----------------------------------------------------------------------------------------
GO
CREATE OR ALTER VIEW dbo.v_bi_employee_performance AS
SELECT 
    e.EmployeeID,
    -- Concaténation propre pour la BI
    e.FirstName + ' ' + e.LastName AS SalesRep,
    e.Title AS EmployeeRole,
    -- Dimension Géographique (D'où viennent leurs clients)
    c.Country AS ClientCountry,
    -- KPI de Volume : Nombre de commandes gérées
    COUNT(DISTINCT o.OrderID) AS TotalOrdersManaged,
    -- KPI de Valeur Absolue : Chiffre d'affaires net sécurisé et arrondi
    ROUND(SUM(od.Quantity * od.UnitPrice * (1 - CAST(od.Discount AS DECIMAL(10,4)))), 2) AS TotalRevenueGenerated,
    -- KPI d'Efficacité : Le panier moyen vendu par ce commercial
    ROUND(SUM(od.Quantity * od.UnitPrice * (1 - CAST(od.Discount AS DECIMAL(10,4)))) / COUNT(DISTINCT o.OrderID), 2) AS AverageRevenuePerOrder
FROM dbo.Employees e 
INNER JOIN dbo.Orders o ON e.EmployeeID = o.EmployeeID 
INNER JOIN dbo.Customers c ON o.CustomerID = c.CustomerID
INNER JOIN dbo.[Order Details] od ON o.OrderID = od.OrderID
GROUP BY 
    e.EmployeeID,
    e.FirstName + ' ' + e.LastName,
    e.Title,
    c.Country;
