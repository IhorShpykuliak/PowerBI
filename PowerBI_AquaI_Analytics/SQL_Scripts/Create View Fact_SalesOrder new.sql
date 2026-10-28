/*******************************************************************************
  Script Name:  Create_Fact_SalesOrder.sql
  Description:  Creates Fact view for Sales Orders (Fact_SalesOrder)
                with full Kit explosion, component quantities, and correct component codes.
  Database:     Tippers
  Author:       Ihor Shpykuliak
*******************************************************************************/

USE [Tippers];
GO

-- Drop existing Fact_SalesOrder view if it exists
IF OBJECT_ID('dbo.Fact_SalesOrder', 'V') IS NOT NULL
    DROP VIEW dbo.Fact_SalesOrder;
GO

CREATE VIEW dbo.Fact_SalesOrder AS
SELECT 
    -- Product Codes & IDs (Resolved to Component if Kit, or Standard Product)
    CompProd.C_CODE                              AS ProductCode,
    P.C_CODE                                     AS KitParentProductCode,
    KC.C_PRODUCT                                 AS ProductID,
    SOL.C_PRODUCT                                AS KitParentProductID,
    
    SOL.C_ID                                     AS SalesOrderLineID,    -- Unique Line ID / Foreign Key
    SO.C_ID                                      AS SalesOrderID,        -- Header ID
    LTRIM(RTRIM(SO.C_NUMBER))                    AS OrderNumber,         -- Business Document Reference
    
    -- Foreign Keys to Conformed Dimensions (for Power BI relationships)
    CAST(SO.C_DATE AS DATE)                      AS SODateKey,           -- Order Date -> Dim_Date[Date]
    SO.C_CUSTOMER                                AS CustomerID,          -- Customer -> Dim_Customer[CustomerID]
    SO.C_BRANCH                                  AS BranchID,            -- Branch -> Dim_Branch[BranchID]
    SO.C_SALESREP                                AS SalesRepID,          -- Sales Representative -> Dim_SalesRep[SalesRepID]
    SO.C_SOURCEFORECASTORDER                     AS ForecastOrder,       -- Source Forecast Order reference
    
    -- Status & Business Category Logic
    SO.C_ORDERTYPE                               AS OrderTypeID,
    SO.C_WORKFLOWSTATUS                          AS WorkflowStatusID,

    -- Fact Metrics: Multiplied by both Order Quantity and Component Quantity ratio
    ISNULL(SOL.C_QUANTITY, 0) * ISNULL(KC.C_QTY_MULTIPLIER, 1)            AS QuantityOrdered,
    ISNULL(SOL.C_QUANTITYOUTSTANDING, 0) * ISNULL(KC.C_QTY_MULTIPLIER, 1) AS QuantityOutstanding,
    
    -- Financial Values (Maintained at Sales Line Level without splitting values)
    ISNULL(SOL.C_NETAMOUNT, 0)                   AS LineNetAmount,
    COALESCE(SOL.C_DUEDATE, SO.C_DUEDATE)        AS EffectiveDueDate

FROM [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_SALESORDER] SO WITH (NOLOCK)
INNER JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_SALESORDER_LINE] SOL WITH (NOLOCK)
    ON SOL.C__OWNER_ = SO.C_ID
INNER JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCT] P WITH (NOLOCK)
    ON P.C_ID = SOL.C_PRODUCT
-- Fully explode Kit into components with total multiplier, or pass regular product 1-to-1
OUTER APPLY (
    -- 1. If it's a Kit (Type 3), fetch its components and their recipe quantities
    SELECT C_PRODUCT, C_QUANTITY AS C_QTY_MULTIPLIER
    FROM [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCT_KITCOMPONENT] 
    WHERE C__OWNER_ = P.C_ID AND P.C_TYPE = 3
    
    UNION ALL
    
    -- 2. If it is a standard non-kit product, return its own ID with multiplier 1.0
    SELECT P.C_ID, 1.0 
    WHERE P.C_TYPE <> 3
) KC
-- Join to get the actual Product details for the resolved ProductID (Component or Standard Product)
INNER JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCT] CompProd WITH (NOLOCK)
    ON CompProd.C_ID = KC.C_PRODUCT
LEFT JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCTDEPARTMENT] PD WITH (NOLOCK)
    ON PD.C_ID = P.C_DEPARTMENT
LEFT JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCTDEPARTMENTGROUP] PDG WITH (NOLOCK)
    ON PD.C_GROUP = PDG.C_ID
WHERE 1=1
     --AND SO.C_NUMBER = 'AI--SO0000822';
GO