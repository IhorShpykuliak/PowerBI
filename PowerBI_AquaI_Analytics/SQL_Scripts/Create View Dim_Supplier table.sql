/*******************************************************************************
  Script Name:  Create_Dim_Supplier.sql
  Description:  Creates a clean Dimension view for Suppliers (Dim_Supplier)
                from Intact IQ ERP system (dbo.T_SUPPLIER) for Power BI Star Schema.
  Database:     Tippers
  Author:       Ihor Shpykuliak
*******************************************************************************/

USE [Tippers];
GO

-- 1. Drop existing Dim_Supplier view if it exists
IF OBJECT_ID('dbo.Dim_Supplier', 'V') IS NOT NULL
    DROP VIEW dbo.Dim_Supplier;
GO

-- 2. Create Dim_Supplier View
CREATE VIEW dbo.Dim_Supplier AS
SELECT 
    -- Primary Surrogate Key for Relationships
    S.C_ID                                     AS SupplierID,           -- Foreign key to Fact_PurchaseOrder (PO.C_SUPPLIER)
    
    -- Supplier Identifiers & Core Business Attributes
    LTRIM(RTRIM(S.C_CODE))                     AS SupplierCode,         -- Unique Supplier Account Code
    LTRIM(RTRIM(S.C_NAME))                     AS SupplierName,         -- Registered Company Name
    LTRIM(RTRIM(S.C_TRADINGNAME))              AS TradingName,          -- Trading/Brand Name
    
    -- Status & Categorization
    S.C_WORKFLOWSTATUS                         AS WorkflowStatusID,     -- ID for Workflow Status
    S.C_CREDITSTATUS                           AS CreditStatusID,       -- ID for Credit Status
    S.C_CATEGORY                               AS SupplierCategoryID,   -- ID for Category
    S.C_TYPE                                   AS SupplierTypeID,       -- ID for Type
    S.C_HOMEBRANCH                             AS HomeBranchID,         -- Preferred Branch
    
    -- Financial & Trading Settings
    S.C_DEFAULTCURRENCY                        AS CurrencyID,           -- Primary Currency ID
    S.C_D_HIDEPRICESONPURCHASEORDERS           AS IsHidePricesOnPO,     -- Flag: Hide prices on PO forms
    S.C_D_HIDESUPPLIER                         AS IsSupplierHidden,     -- Flag: Hidden status
    S.C_D_DISABLEONEOFFSPECIALS                AS IsOneOffSpecialsDisabled,
    
    -- Contact Information
    LTRIM(RTRIM(S.C_ADDRESS))                  AS Address,
    LTRIM(RTRIM(S.C_PHONE))                    AS Phone,
    LTRIM(RTRIM(S.C_MOBILE))                   AS Mobile,
    LTRIM(RTRIM(S.C_EMAILADDRESS))             AS EmailAddress,
    LTRIM(RTRIM(S.C_HOMEPAGE))                 AS WebsiteURL

FROM [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_SUPPLIER] S WITH (NOLOCK)
WHERE 1=1
    AND S.C_NAME IS NOT NULL; -- Exclude corrupt/empty system records
GO