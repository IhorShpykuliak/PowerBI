;WITH IQAvgCost AS
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
)
SELECT
    p.C_ID AS ProductID,
    p.C_CODE AS ProdCode,
    p.C_DESCRIPTION AS ProdDescription,
    PD.C_DESCRIPTION AS Department,

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

    -- Габариты и объем (CBM)
    m.C_LENGTH AS Length,
    m.C_WIDTH AS Width,
    m.C_HEIGHT AS Height,
    m.C_GROSSWEIGHT AS GrossWeight,
    CAST((m.C_LENGTH * m.C_WIDTH * m.C_HEIGHT) / 1000000000.0 AS DECIMAL(18,4)) AS CBM,

    -- Стоковые показатели
    CONVERT(DOUBLE PRECISION, ISNULL(pstats.C_STOCKLEVEL, 0)) AS StockLevel,
    CONVERT(DOUBLE PRECISION, ISNULL(pstats.C_OUTSTANDINGSALESORDERS, 0)) AS OutstandingSO,
    CONVERT(DOUBLE PRECISION, ISNULL(pstats.C_OUTSTANDINGPURCHASEORDERS, 0)) AS OutstandingPO,
    CONVERT(DOUBLE PRECISION, ISNULL(pstats.C_EFFECTIVESTOCKLEVEL, 0)) AS EffectiveStockLevel,

    -- Данные YTD
    CAST(ISNULL(Ytd.TotalQty, 0) AS INT) AS SalesYtdQty,
    CAST(ISNULL(Ytd.TotalSales, 0) AS DECIMAL(18,2)) AS SalesYtdAmount,
    CONVERT(DOUBLE PRECISION, ISNULL(SPY.QtyInvoiced, 0)) AS QtyPurchasedYtd,

    -- Цены и себестоимость
    ex.exRate AS ExchangeRateUSD,
    CAST(PP.C_LISTPRICEACTUAL AS DECIMAL(18,2)) AS ListPriceActual,
    CAST(CASE WHEN CUR.C_CODE = 'USD' THEN PPalt.C_LISTPRICEACTUAL ELSE 0 END AS DECIMAL(18,2)) AS USDListPrice,
    ISNULL(comc.C_D_RATE, 0) AS DutyRatePercentage,
    cc.C_STANDARDCOST AS StandardCost,
    i.C_NEWCOSTPRICE AS AvgCost,

    -- Расчет Landed Cost
    CAST(
        CASE 
            WHEN CUR.C_CODE = 'USD' 
                 AND PPalt.C_LISTPRICEACTUAL IS NOT NULL 
                 AND (m.C_LENGTH * m.C_WIDTH * m.C_HEIGHT) > 0
                 AND ex.exRate > 0
            THEN (
                    (CEILING((PPalt.C_LISTPRICEACTUAL / ex.exRate) * 100) / 100.0) +
                    (((m.C_LENGTH * m.C_WIDTH * m.C_HEIGHT) / 1000000000.0) / 66.0 * 6000.0)
                 ) * (1 + ISNULL(comc.C_D_RATE, 0) / 100.0)
            ELSE i.C_NEWCOSTPRICE
        END AS DECIMAL(18,2)
    ) AS CalculatedLandedCost

FROM [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCT] p WITH (NOLOCK)
CROSS JOIN ExchangeRate ex
LEFT JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCT_STATISTICS] pstats WITH (NOLOCK) ON pstats.C_ID = p.C_STATISTICS
LEFT JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCT_PURCHASING] pp WITH (NOLOCK) ON pp.C_ID = p.C_PURCHASING
LEFT JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_SUPPLIER] s WITH (NOLOCK) ON s.C_ID = pp.C_DEFAULTSUPPLIER
LEFT JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCTDEPARTMENT] PD WITH (NOLOCK) ON PD.C_ID = p.C_DEPARTMENT
LEFT JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCTDEPARTMENTGROUP] PDG WITH (NOLOCK) ON PD.C_GROUP = PDG.C_ID
LEFT JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCT_COSTINGS] cc WITH (NOLOCK) ON cc.C_ID = p.C_COSTINGS
LEFT JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCT_MEASUREMENTS] m WITH (NOLOCK) ON p.C_MEASUREMENTS = m.C_ID
LEFT JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCT_ALTERNATEPURCHASINGINFO] PI WITH (NOLOCK) ON PI.C__OWNER_ = p.C_ID
LEFT JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCT_PURCHASING] PPAlt WITH (NOLOCK) ON PPAlt.C_ID = PI.C_ID
LEFT JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_CURRENCY] CUR WITH (NOLOCK) ON CUR.C_ID = PPalt.C_LISTPRICECURRENCY
LEFT JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCT_IMPORTDUTYSETTINGS] com WITH (NOLOCK) ON com.C_ID = p.C_IMPORTDUTYSETTINGS
LEFT JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_IS_COMMODITYCODE] comc WITH (NOLOCK) ON comc.C_ID = com.C_COMMODITYCODE
LEFT JOIN IQAvgCost i ON i.C_PRODUCT = p.C_ID
LEFT JOIN SalesYTD Ytd ON Ytd.Product_ID = p.C_ID
LEFT JOIN SupplierPurchasingYTD SPY ON SPY.Product_ID = p.C_ID
WHERE p.C_TYPE NOT IN (15, 2, 6, 19, 10, 18)
  AND PDG.C_CODE = 'AQUAI';