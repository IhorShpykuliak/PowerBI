/*******************************************************************************
  Script Name:  Create_Fact_SalesAnalysis.sql
  Description:  Creates Fact View for Sales Analysis (Fact_SalesAnalysis)
                from Archive table Tippers_SalesAnalysis.
                Filters strictly for AQUAI department/branch transactions.
  Database:     Tippers
  Author:       Ihor Shpykuliak
*******************************************************************************/

USE [Tippers];
GO

IF OBJECT_ID('dbo.Fact_SalesAnalysis', 'V') IS NOT NULL
    DROP VIEW dbo.Fact_SalesAnalysis;
GO

CREATE VIEW dbo.Fact_SalesAnalysis AS
SELECT 
    -- Primary Fact Surrogate Keys & Document Info
    SA.[Line_id]                                AS SalesAnalysisLineID,
    SA.[ID]                                     AS DocumentHeaderID,
    LTRIM(RTRIM(SA.[Number]))                   AS DocumentNumber,
    SA.[DocType]                                AS DocType,
    
    -- Foreign Keys to Conformed Dimensions
    CAST(SA.[DATE] AS DATE)                     AS SalesDateKey,       -- -> Dim_Date[Date]
    SA.[Product_ID]                             AS ProductID,          -- -> Dim_Product[ProductID]
    SA.[Customer_ID]                            AS CustomerID,         -- -> Dim_Customer[CustomerID]
    SA.[Branch_ID]                              AS BranchID,           -- -> Dim_Branch[BranchID]
    SA.[Sales_Order_By_ID]                      AS SalesRepID,         -- -> Dim_SalesRep[SalesRepID]
    SA.[StockBranchID]                          AS StockBranchID,      -- -> Dim_Branch[BranchID]
    SA.[OriginalBranchID]                       AS OriginalBranchID,   -- -> Dim_Branch[BranchID]
    
    -- Business Identifiers & Attributes
    LTRIM(RTRIM(SA.[CustomerCode]))            AS CustomerCode,
    LTRIM(RTRIM(SA.[ProductCode]))             AS ProductCode,
    SA.[CostCentre]                             AS CostCentre,
    SA.[DepartmentID]                           AS DepartmentID,
    SA.[OrderSource]                            AS OrderSource,
    SA.[Sales_Order_Number]                     AS SalesOrderNumber,
    
    -- Measures & Fact Metrics
    ISNULL(SA.[Quantity], 0)                    AS QuantitySold,
    ISNULL(SA.[NetAmountLessDiscountBase], 0)   AS NetSalesAmount,
    ISNULL(SA.[NetCostBase], 0)                 AS NetCostAmount,
    
    -- Calculated GP Value
    (ISNULL(SA.[NetAmountLessDiscountBase], 0) 
     - ISNULL(SA.[NetCostBase], 0))             AS GrossProfitValue,
     
    -- Additional Cost & Rebate Metrics
    ISNULL(SA.[netSellingCostBase], 0)          AS NetSellingCostAmount,
    ISNULL(SA.[AverageCost], 0)                 AS AverageCost,
    ISNULL(SA.[AveragePerUnitCost], 0)          AS AveragePerUnitCost,
    ISNULL(SA.[PotentialRebateAmount], 0)       AS PotentialRebateAmount,
    ISNULL(SA.[SellingCostRebate], 0)           AS SellingCostRebate,
    ISNULL(SA.[SupplierPriceSupportAmount], 0)  AS SupplierPriceSupportAmount,
    
    -- Unit Prices
    ISNULL(SA.[Original_Price_Per_Unit], 0)     AS OriginalPricePerUnit,
    ISNULL(SA.[Selling_Price_Per_Unit], 0)      AS SellingPricePerUnit

FROM [Intact_IQ_Walter_Tipper_Ltd_Archive].[dbo].[Tippers_SalesAnalysis] SA WITH (NOLOCK)
WHERE 1=1
  AND (SA.[CostCentre] = 'AI' OR SA.[BranchCode] = 'AQI')  -- Фильтр строго для AquaI
  AND (SA.[CustomerCode] IS NULL OR UPPER(LTRIM(RTRIM(SA.[CustomerCode]))) NOT LIKE 'INTERCO%')
  AND (SA.[CustomerCode] IS NULL OR UPPER(LTRIM(RTRIM(SA.[CustomerCode]))) != 'WALT0001');
GO