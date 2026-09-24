/*******************************************************************************
  Script Name:  Create_Dim_Branch.sql
  Description:  Creates Dimension view for Branches/Locations (Dim_Branch)
                from Intact IQ ERP system (dbo.T_BRANCH).
  Database:     Tippers
  Author:       Ihor Shpykuliak
*******************************************************************************/

USE [Tippers];
GO

IF OBJECT_ID('dbo.Dim_Branch', 'V') IS NOT NULL
    DROP VIEW dbo.Dim_Branch;
GO

CREATE VIEW dbo.Dim_Branch AS
SELECT 
    B.C_ID                                     AS BranchID,             -- Primary Surrogate Key
    LTRIM(RTRIM(B.C_CODE))                     AS BranchCode,
    LTRIM(RTRIM(B.C_Description))              AS BranchName,
    LTRIM(RTRIM(B.C_ADDRESS))                  AS BranchAddress
FROM [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_BRANCH] B WITH (NOLOCK);
GO