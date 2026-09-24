/*******************************************************************************
  Script Name:  Create_Fact_SalesOrder.sql
  Description:  Creates Fact view for Sales Orders (Fact_SalesOrder)
                linking to Conformed Dimensions in the Tippers Star Schema.
  Database:     Tippers
  Author:       Ihor Shpykuliak
*******************************************************************************/

USE [Tippers];
GO

-- 1. Drop existing Fact_SalesOrder view if it exists
IF OBJECT_ID('dbo.Fact_SalesOrder', 'V') IS NOT NULL
    DROP VIEW dbo.Fact_SalesOrder;
GO

-- 2. Create Fact_SalesOrder View
CREATE VIEW dbo.Fact_SalesOrder AS
SELECT 
    -- Primary Fact Surrogate Keys
    SOL.C_ID                                   AS SalesOrderLineID,    -- Foreign Key / Unique Line ID
    SO.C_ID                                    AS SalesOrderID,        -- Header ID
    LTRIM(RTRIM(SO.C_NUMBER))                   AS OrderNumber,         -- Business Document Ref
    
    -- Foreign Keys to Conformed Dimensions
    CAST(SO.C_DATE AS DATE)                    AS SODateKey,           -- -> Dim_Date[Date]
    SOL.C_PRODUCT                              AS ProductID,           -- -> Dim_Product[ProductID]
    SO.C_CUSTOMER                             AS CustomerID,          -- -> Dim_Customer[CustomerID]
    SO.C_BRANCH                                AS BranchID,            -- -> Dim_Branch[BranchID]
    SO.C_SALESREP                              AS SalesRepID,          -- -> Dim_SalesRep[SalesRepID]
    
    -- Status & Business Category Logic
    SO.C_ORDERTYPE                             AS OrderTypeID,
    SO.C_WORKFLOWSTATUS                        AS WorkflowStatusID,
    CASE 
        WHEN SO.C_ORDERTYPE = 9247139882382 AND SO.C_WORKFLOWSTATUS = 9251359563444 
        THEN 'Forecast Order'
        ELSE 'Standard Sales Order'
    END                                        AS OrderCategory,

    -- Fact Metrics
    ISNULL(SOL.C_QUANTITY, 0)                  AS QuantityOrdered,
    ISNULL(SOL.C_NETAMOUNT, 0)                 AS LineNetAmount

FROM [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_SALESORDER] SO WITH (NOLOCK)
INNER JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_SALESORDER_LINE] SOL WITH (NOLOCK)
    ON SOL.C__OWNER_ = SO.C_ID
INNER JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCT] P WITH (NOLOCK)
    ON P.C_ID = SOL.C_PRODUCT
INNER JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCTDEPARTMENT] PD WITH (NOLOCK)
    ON PD.C_ID = P.C_DEPARTMENT
INNER JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCTDEPARTMENTGROUP] PDG WITH (NOLOCK)
    ON PD.C_GROUP = PDG.C_ID
WHERE 1=1
    AND PDG.C_CODE = 'AQUAI'; -- Filter strictly for AQUAI department group
GO