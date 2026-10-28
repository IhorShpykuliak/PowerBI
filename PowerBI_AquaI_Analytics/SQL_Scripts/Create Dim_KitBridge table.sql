/*******************************************************************************
  Script Name:  Create_Dim_KitBridge.sql
  Description:  Creates Bridge Table view to map Kits to their Components 
                and standard products to themselves.
  Database:     Tippers
  Author:       Ihor Shpykuliak
*******************************************************************************/

USE [Tippers];
GO

IF OBJECT_ID('dbo.Dim_KitBridge', 'V') IS NOT NULL
    DROP VIEW dbo.Dim_KitBridge;
GO

CREATE VIEW dbo.Dim_KitBridge AS
-- 1. Components of Type 3 Kits (expanded with recipe quantities)
SELECT 
    P.C_ID                                       AS ParentProductID,     -- Kit Product ID (stored in Sales Order)
    KC.C_PRODUCT                                 AS ComponentProductID,  -- Component Product ID
    KC.C_QUANTITY                                AS QtyMultiplier        -- Recipe multiplier quantity
FROM [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCT] P WITH (NOLOCK)
INNER JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCT_KITCOMPONENT] KC WITH (NOLOCK)
    ON KC.C__OWNER_ = P.C_ID
WHERE P.C_TYPE = 3

UNION ALL

-- 2. Standard non-kit products (self-reference with multiplier 1.0)
SELECT 
    P.C_ID                                       AS ParentProductID,
    P.C_ID                                       AS ComponentProductID,
    1.0                                          AS QtyMultiplier
FROM [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCT] P WITH (NOLOCK)
WHERE P.C_TYPE <> 3;
GO