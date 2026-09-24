/*******************************************************************************
  Script Name:  Create_Dim_Customer.sql
  Description:  Creates Dimension view for Customers (Dim_Customer)
                from Intact IQ ERP system (dbo.T_CUSTOMER).
  Database:     Tippers
  Author:       Ihor Shpykuliak
*******************************************************************************/

USE [Tippers];
GO

IF OBJECT_ID('dbo.Dim_Customer', 'V') IS NOT NULL
    DROP VIEW dbo.Dim_Customer;
GO

CREATE VIEW dbo.Dim_Customer AS
SELECT 
    C.C_ID                                     AS CustomerID,           -- Primary Surrogate Key
    LTRIM(RTRIM(C.C_CODE))                     AS CustomerCode,
    LTRIM(RTRIM(C.C_NAME))                     AS CustomerName,
    LTRIM(RTRIM(C.C_TRADINGNAME))              AS TradingName,
    
    C.C_WORKFLOWSTATUS                         AS WorkflowStatusID,
    C.C_CREDITSTATUS                           AS CreditStatusID,
    C.C_CATEGORY                               AS CustomerCategoryID,
    C.C_HOMEBRANCH                             AS HomeBranchID,
    
    LTRIM(RTRIM(C.C_ADDRESS))                  AS Address,
    LTRIM(RTRIM(C.C_PHONE))                    AS Phone,
    LTRIM(RTRIM(C.C_EMAILADDRESS))             AS EmailAddress
FROM [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_CUSTOMER] C WITH (NOLOCK)
WHERE 1=1
    AND C.C_NAME IS NOT NULL;
GO