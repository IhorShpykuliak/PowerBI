/*******************************************************************************
  Script Name:  Create_Dim_SalesRep.sql
  Description:  Creates Dimension view for Sales Representatives (Dim_SalesRep)
                from Intact IQ ERP system (dbo.T_SALESREP).
  Database:     Tippers
  Author:       Ihor Shpykuliak
*******************************************************************************/

USE [Tippers];
GO

IF OBJECT_ID('dbo.Dim_SalesRep', 'V') IS NOT NULL
    DROP VIEW dbo.Dim_SalesRep;
GO

CREATE VIEW dbo.Dim_SalesRep AS
SELECT 
    SR.C_ID                                    AS SalesRepID,           -- Primary Surrogate Key
    LTRIM(RTRIM(SR.C_CODE))                    AS SalesRepCode,
    LTRIM(RTRIM(SR.C_NAME))                    AS SalesRepName
FROM [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_SALESREP] SR WITH (NOLOCK);
GO