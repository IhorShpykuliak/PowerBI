/*******************************************************************************
  Script Name:  Create_Dim_Product.sql
  Description:  Creates Conformed Dimension view for Products (Dim_Product)
                with integrated costs, stock statistics, YTD, and Kit components.
  Database:     Tippers
  Author:       Ihor Shpykuliak
*******************************************************************************/

USE [Tippers];
GO

-- Drop existing Dim_Product view if it exists
IF OBJECT_ID('dbo.Dim_Product', 'V') IS NOT NULL
    DROP VIEW dbo.Dim_Product;
GO

CREATE VIEW dbo.Dim_Product AS
WITH IQAvgCost AS
(
    SELECT 
        sub1.C_PRODUCT,
        SUM(C_NEWSTOCKVALUE) / NULLIF(SUM(C_NEWSTOCKLEVEL), 0) AS C_NEWCOSTPRICE
    FROM
    (
        SELECT 
            ac.C_PRODUCT,
            ac.C_NEWSTOCKVALUE,
            ac.C_NEWSTOCKLEVEL,
            ROW_NUMBER() OVER (
                PARTITION BY ac.C_PRODUCT, ac.C_BRANCH 
                ORDER BY ac.C_DATE DESC
            ) AS rn
        FROM [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCTAVERAGECOSTUPDATE] ac WITH (NOLOCK)
        WHERE ac.C_BRANCH = 4337992263053
    ) sub1
    WHERE rn = 1
    GROUP BY sub1.C_PRODUCT
),
SalesYTD AS
(
    SELECT 
        [Product_ID],
        SUM([Quantity]) AS TotalQty,
        SUM([NetAmountLessDiscountBase]) AS TotalSales
    FROM [Intact_IQ_Walter_Tipper_Ltd_Archive].[dbo].[Tippers_SalesAnalysis] WITH (NOLOCK)
    WHERE [Date] >= DATEADD(YEAR, -1, GETDATE())
    GROUP BY [Product_ID]
),
SupplierPurchasingYTD AS
(
    SELECT 
        PDNL.C_PRODUCT AS Product_ID,
        SUM(PDNL.C_QUANTITYINVOICED) AS QtyInvoiced
    FROM [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PURCHASEDELIVERYNOTE_LINE] PDNL WITH (NOLOCK)
    INNER JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PURCHASEDELIVERYNOTE] PDN WITH (NOLOCK)
        ON PDN.C_ID = PDNL.C__OWNER_
    WHERE PDN.C_DATE >= DATEADD(YEAR, -1, GETDATE())
    GROUP BY PDNL.C_PRODUCT
),
ExchangeRate AS
(
    SELECT C_PURCHASELEDGERRATE AS exRate
    FROM [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_IS_CURRENCYRATEDEFINITION_CURRENCYRATEDEFINITIONCURRENCYINFO] WITH (NOLOCK)
    WHERE C_ID = 524883787719020
),
USDAltPurchasing AS
(
    SELECT 
        PI.C__OWNER_ AS Product_ID,
        PPAlt.C_LISTPRICEACTUAL,
        CUR.C_CODE AS CurrencyCode,
        ROW_NUMBER() OVER (
            PARTITION BY PI.C__OWNER_ 
            ORDER BY PPAlt.C_LISTPRICEACTUAL DESC
        ) AS rn
    FROM [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCT_ALTERNATEPURCHASINGINFO] PI WITH (NOLOCK)
    INNER JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCT_PURCHASING] PPAlt WITH (NOLOCK) 
        ON PPAlt.C_ID = PI.C_ID
    INNER JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_CURRENCY] CUR WITH (NOLOCK) 
        ON CUR.C_ID = PPalt.C_LISTPRICECURRENCY
    WHERE CUR.C_CODE = 'USD'
),
KitComponentsAgg AS
(
    SELECT 
        KIT.C__OWNER_ AS ParentProductID,
        STRING_AGG(CONCAT(CompProd.C_CODE, ' (qty: ', CAST(CAST(KIT.C_QUANTITY AS INT) AS VARCHAR(10)), ')'), ', ') AS KitComponentsList
    FROM [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCT_KITCOMPONENT] KIT WITH (NOLOCK)
    INNER JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCT] CompProd WITH (NOLOCK) 
        ON CompProd.C_ID = KIT.C_PRODUCT
    GROUP BY KIT.C__OWNER_
)
SELECT
    p.C_ID AS ProductID,
    p.C_CODE AS ProdCode,
    p.C_DESCRIPTION AS ProdDescription,
    PD.C_DESCRIPTION AS Department,

    -- Product Type mapping
    CASE p.C_TYPE 
        WHEN 0  THEN 'Standard'
        WHEN 4  THEN 'Special'
        WHEN 7  THEN 'Assembly'
        WHEN 3  THEN 'Kit'
        WHEN 11 THEN 'Linear'
        WHEN 12 THEN 'LinearCon'
        WHEN 21 THEN 'Index'
        ELSE CAST(p.C_TYPE AS VARCHAR(10)) 
    END AS ProductType,

    s.C_NAME AS SupplierName,
    s.C_CODE AS SupplierCode,

    -- Stocking Status mapping
    CASE p.C_STOCKINGSTATUS 
        WHEN 0 THEN 'Stocked'
        WHEN 5 THEN 'Discontinued Immediately'
        WHEN 4 THEN 'Discontinued After Stock Is Sold'
        WHEN 1 THEN 'Non Stocked'
        WHEN 7 THEN 'Not Applicable' 
        WHEN 2 THEN 'Superseded'
        ELSE CAST(p.C_STOCKINGSTATUS AS VARCHAR(10)) 
    END AS StockingStatus,

    p.C_D_SEARCHKEYWORDS AS SearchKeywords,
    PP.C_SUPPLIERPRODUCTCODE AS SupplierProductCode,
    kc.KitComponentsList AS KitComponents,

    -- Measurements & CBM calculation
    m.C_LENGTH AS Length,
    m.C_WIDTH AS Width,
    m.C_HEIGHT AS Height,
    m.C_GROSSWEIGHT AS GrossWeight,
    CAST((m.C_LENGTH * m.C_WIDTH * m.C_HEIGHT) / 1000000000.0 AS DECIMAL(18,4)) AS CBM,

    -- Stock Statistics
    CONVERT(DOUBLE PRECISION, ISNULL(pstats.C_STOCKLEVEL, 0)) AS StockLevel,
    CONVERT(DOUBLE PRECISION, ISNULL(pstats.C_OUTSTANDINGSALESORDERS, 0)) AS OutstandingSO,
    CONVERT(DOUBLE PRECISION, ISNULL(pstats.C_OUTSTANDINGPURCHASEORDERS, 0)) AS OutstandingPO,
    CONVERT(DOUBLE PRECISION, ISNULL(pstats.C_EFFECTIVESTOCKLEVEL, 0)) AS EffectiveStockLevel,

    -- Year-to-Date (YTD) Metrics
    CAST(ISNULL(Ytd.TotalQty, 0) AS INT) AS SalesYtdQty,
    CAST(ISNULL(Ytd.TotalSales, 0) AS DECIMAL(18,2)) AS SalesYtdAmount,
    CONVERT(DOUBLE PRECISION, ISNULL(SPY.QtyInvoiced, 0)) AS QtyPurchasedYtd,

    -- Price & Cost Metrics
    ex.exRate AS ExchangeRateUSD,
    CAST(PP.C_LISTPRICEACTUAL AS DECIMAL(18,2)) AS ListPriceActual,
    CAST(ISNULL(altUSD.C_LISTPRICEACTUAL, 0) AS DECIMAL(18,2)) AS USDListPrice,
    ISNULL(comc.C_D_RATE, 0) AS DutyRatePercentage,
    cc.C_STANDARDCOST AS StandardCost,
    i.C_NEWCOSTPRICE AS AvgCost,

    -- Calculated Landed Cost
    CAST(
        CASE 
            WHEN altUSD.CurrencyCode = 'USD' 
                 AND altUSD.C_LISTPRICEACTUAL IS NOT NULL 
                 AND (m.C_LENGTH * m.C_WIDTH * m.C_HEIGHT) > 0
                 AND ex.exRate > 0
            THEN (
                    (CEILING((altUSD.C_LISTPRICEACTUAL / ex.exRate) * 100) / 100.0) +
                    (((m.C_LENGTH * m.C_WIDTH * m.C_HEIGHT) / 1000000000.0) / 66000.0)
                 ) * (1 + ISNULL(comc.C_D_RATE, 0) / 100.0)
            ELSE i.C_NEWCOSTPRICE
        END AS DECIMAL(18,2)
    ) AS CalculatedLandedCost,

    -- Additional Descriptive Attributes
    PP.[C_SUPPLIERPRODUCTCODE] AS AquaICode,
    PP.[C_SUPPLIERPRODUCTDESCRIPTION] AS AquaIDescription,
    P.C_D_WyndamCode AS WyndamCode,
    P.C_D_WyndamDescription AS WyndamDescription,
    P.C_ManufacturerProductCode AS SupplierStockCode,
    PP.C_D_MOQ AS MOQ,
    p.[C_D_PERCENTAGEGROWTH] AS GrowthFactor,
    pp.C_PACKSIZE AS CartonQTY,
    p.[C_D_COREPRODUCT] AS CoreProduct
    
FROM [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCT] p WITH (NOLOCK)
CROSS JOIN ExchangeRate ex
LEFT JOIN KitComponentsAgg kc ON kc.ParentProductID = p.C_ID
LEFT JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCT_STATISTICS] pstats WITH (NOLOCK) ON pstats.C_ID = p.C_STATISTICS
LEFT JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCT_PURCHASING] pp WITH (NOLOCK) ON pp.C_ID = p.C_PURCHASING
LEFT JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_SUPPLIER] s WITH (NOLOCK) ON s.C_ID = pp.C_DEFAULTSUPPLIER
LEFT JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCTDEPARTMENT] PD WITH (NOLOCK) ON PD.C_ID = p.C_DEPARTMENT
LEFT JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCTDEPARTMENTGROUP] PDG WITH (NOLOCK) ON PD.C_GROUP = PDG.C_ID
LEFT JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCT_COSTINGS] cc WITH (NOLOCK) ON cc.C_ID = p.C_COSTINGS
LEFT JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCT_MEASUREMENTS] m WITH (NOLOCK) ON p.C_MEASUREMENTS = m.C_ID
LEFT JOIN USDAltPurchasing altUSD ON altUSD.Product_ID = p.C_ID AND altUSD.rn = 1
LEFT JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCT_IMPORTDUTYSETTINGS] com WITH (NOLOCK) ON com.C_ID = p.C_IMPORTDUTYSETTINGS
LEFT JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_IS_COMMODITYCODE] comc WITH (NOLOCK) ON comc.C_ID = com.C_COMMODITYCODE
LEFT JOIN IQAvgCost i ON i.C_PRODUCT = p.C_ID
LEFT JOIN SalesYTD Ytd ON Ytd.Product_ID = p.C_ID
LEFT JOIN SupplierPurchasingYTD SPY ON SPY.Product_ID = p.C_ID
WHERE p.C_TYPE NOT IN (15, 2, 6, 19, 10, 18);
GO