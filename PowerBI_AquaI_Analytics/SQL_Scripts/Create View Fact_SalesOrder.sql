/*******************************************************************************
  Script Name:  Create_Fact_SalesOrder.sql
  Description:  Creates Fact view for Sales Orders (Fact_SalesOrder)
                linking to Conformed Dimensions with Kit component expansion.
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
    -- Explode Kit components into individual product rows, or keep standard product ID
    ISNULL(KC.C_PRODUCT, SOL.C_PRODUCT)          AS ProductID,
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

    -- Fact Metrics (Multiplied by kit component quantity if applicable)
    ISNULL(SOL.C_QUANTITY, 0) * ISNULL(KC.C_QUANTITY, 1)                  AS QuantityOrdered,
    ISNULL(SOL.C_QUANTITYOUTSTANDING, 0) * ISNULL(KC.C_QUANTITY, 1)       AS QuantityOutstanding,
    ISNULL(SOL.C_NETAMOUNT, 0)                   AS LineNetAmount,
    COALESCE(SOL.C_DUEDATE, SO.C_DUEDATE)        AS EffectiveDueDate

FROM [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_SALESORDER] SO WITH (NOLOCK)
INNER JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_SALESORDER_LINE] SOL WITH (NOLOCK)
    ON SOL.C__OWNER_ = SO.C_ID
INNER JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCT] P WITH (NOLOCK)
    ON P.C_ID = SOL.C_PRODUCT
-- Dynamically expand Kit components (Type 3) or keep regular products as 1-to-1
OUTER APPLY (
    SELECT C_PRODUCT, C_QUANTITY 
    FROM [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCT_KITCOMPONENT] 
    WHERE C__OWNER_ = P.C_ID AND P.C_TYPE = 3
    
    UNION ALL
    
    SELECT P.C_ID, 1.0 
    WHERE P.C_TYPE <> 3
) KC
LEFT JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCTDEPARTMENT] PD WITH (NOLOCK)
    ON PD.C_ID = P.C_DEPARTMENT
LEFT JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCTDEPARTMENTGROUP] PDG WITH (NOLOCK)
    ON PD.C_GROUP = PDG.C_ID
WHERE 1=1
    -- AND PDG.C_CODE = 'AQUAI'; -- Uncomment to filter strictly for AQUAI department group
GO