DECLARE @exRate DECIMAL(18,6);

SET @exRate = (
    SELECT C_PURCHASELEDGERRATE
    FROM T_IS_CURRENCYRATEDEFINITION_CURRENCYRATEDEFINITIONCURRENCYINFO
    WHERE C_ID = 524883787719020
);

;WITH SalesYTD AS
(
    SELECT 
        [Product_ID],
        SUM([Quantity]) AS TotalQty,
        SUM([NetAmountLessDiscountBase]) AS TotalSales
    FROM [Intact_IQ_Walter_Tipper_Ltd_Archive].[dbo].[Tippers_SalesAnalysis] WITH (NOLOCK)
    WHERE [Date] >= DATEADD(YEAR, -1, GETDATE())
    GROUP BY [Product_ID]
),

IQAvgCost AS
(
    SELECT 
        sub1.C_PRODUCT,
        SUM(C_NEWSTOCKVALUE) / NULLIF(SUM(C_NEWSTOCKLEVEL), 0) AS C_NEWCOSTPRICE,
        C_BRANCH,
        MAX(C_DATE) AS d
    FROM
    (
        SELECT 
            ac.*,
            ROW_NUMBER() OVER
            (
                PARTITION BY ac.C_PRODUCT, ac.C_BRANCH 
                ORDER BY ac.C_DATE DESC
            ) AS rn
        FROM [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCTAVERAGECOSTUPDATE] ac WITH (NOLOCK)
        WHERE ac.C_BRANCH = 4337992263053
    ) sub1
    WHERE rn = 1
    GROUP BY 
        sub1.C_PRODUCT,
        C_BRANCH
),

ForecastOrders AS
(
    SELECT 
        SOL.C_PRODUCT AS Product_Id,
        SUM(SOL.C_QUANTITY) AS TotalQTY
    FROM [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_SALESORDER] SO WITH (NOLOCK)
    LEFT JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_SALESORDER_LINE] SOL WITH (NOLOCK)
        ON SOL.C__OWNER_ = SO.C_ID
    WHERE SO.C_ORDERTYPE = 9247139882382
      AND SO.C_WORKFLOWSTATUS = 9251359563444
    GROUP BY 
        SOL.C_PRODUCT
),

SupplierPurchasingYTD AS
(
    SELECT 
        P.C_ID AS Product_ID,
        SUM(PDNL.C_QUANTITYINVOICED) AS QtyInvoiced
    FROM [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PURCHASEDELIVERYNOTE_LINE] PDNL WITH (NOLOCK)
    INNER JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PURCHASEDELIVERYNOTE] PDN WITH (NOLOCK)
        ON PDN.C_ID = PDNL.C__OWNER_
    INNER JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCT] P WITH (NOLOCK)
        ON P.C_ID = PDNL.C_PRODUCT
    INNER JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_SUPPLIER] S WITH (NOLOCK)
        ON S.C_ID = PDN.C_SUPPLIER
    WHERE PDN.C_DATE >= DATEADD(YEAR, -1, GETDATE())
    GROUP BY 
        P.C_ID
)

SELECT
    p.C_ID AS ProdID,
    p.C_CODE AS ProdCode,
    p.C_DESCRIPTION AS ProdDes,
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
    END AS Type,

    s.C_NAME AS Supplier,

    CASE p.C_STOCKINGSTATUS 
        WHEN 0 THEN 'Stocked'
        WHEN 5 THEN 'Discontinued Immediately'
        WHEN 4 THEN 'Discontinued After Stock Is Sold'
        WHEN 1 THEN 'Non Stocked'
        WHEN 7 THEN 'Not Applicable' 
        WHEN 2 THEN 'Superseded'
        ELSE CAST(p.C_STOCKINGSTATUS AS VARCHAR(10)) 
    END AS StockingStatus,

    p.C_D_SEARCHKEYWORDS AS [Search Keywords],
    PP.C_SUPPLIERPRODUCTCODE AS [Supplier Product Code],

    CAST(PP.C_LISTPRICEACTUAL AS DECIMAL(18,2)) AS [List Price Actual],

    CONVERT(DOUBLE PRECISION, pstats.C_STOCKLEVEL) AS StockLevel,
    CONVERT(DOUBLE PRECISION, pstats.C_OUTSTANDINGSALESORDERS) AS OutstandingSO,
    CONVERT(DOUBLE PRECISION, pstats.C_OUTSTANDINGPURCHASEORDERS) AS OutstandingPO,
    CONVERT(DOUBLE PRECISION, pstats.C_EFFECTIVESTOCKLEVEL) AS EffectiveStockLevel,

    CONVERT(DOUBLE PRECISION, FO.TotalQTY) AS ForecastQTY,
    CONVERT(DOUBLE PRECISION, SPY.QtyInvoiced) AS QTY_purchased_YTD,

    CAST(Ytd.TotalQty AS INT) AS SalesYtdQtyCount,
    CAST(ISNULL(Ytd.TotalSales, 0) AS DECIMAL(18,2)) AS SalesYtdTotal,

    CAST(pstats.C_LASTPURCHASE AS DATE) AS LastPurchase,
    CAST(pstats.C_LASTSALE AS DATE) AS LastSale,

    cc.C_STANDARDCOST AS StandardCost,

    i.C_NEWCOSTPRICE AS [Avg Cost]

   
	,m.C_LENGTH
	,m.C_WIDTH
	,m.C_HEIGHT
	,m.C_GROSSWEIGHT
	,(m.C_LENGTH * m.C_WIDTH * m.C_HEIGHT)/1000000000 as 'Total CBM'
	,((m.C_LENGTH * m.C_WIDTH * m.C_HEIGHT)/1000000000)/66* 6000  as '6k 66CB Per cost'
	, @exRate AS USDExRate
	,cast (case when CUR.C_CODE = 'USD' then  PPalt.[C_LISTPRICEACTUAL] else 0 end as decimal(18,2))  AS 'USD List Price'
	 ,isnull(comc.C_D_RATE,0) as 'DutyRatePercentage'
--	-- ,CUR.C_CODE AS 'Currency'
--,cast (CASE 
--    WHEN CUR.C_CODE = 'USD' 
--        THEN CEILING((PPalt.[C_LISTPRICEACTUAL] / @exRate) * 100) / 100.0
--    ELSE 0 
-- END + (((m.C_LENGTH * m.C_WIDTH * m.C_HEIGHT)/1000000000)/66* 6000) as decimal(18,2)) as ' test Land Cost'

-- ,CAST(
--    (
--        (
--            CASE 
--                WHEN CUR.C_CODE = 'USD' 
--                    THEN CEILING((PPAlt.C_LISTPRICEACTUAL / @exRate) * 100) / 100.0
--                ELSE 0 
--            END
--            +
--            (((m.C_LENGTH * m.C_WIDTH * m.C_HEIGHT) / 1000000000) / 66 * 6000)
--        )
--        *
--        (1 + ISNULL(comc.C_D_RATE, 0) / 100.0)
--    )
--    AS DECIMAL(18,2)
--) AS [Landed Cost]

,CAST(
    CASE
        WHEN CUR.C_CODE <> 'USD'
             OR PPAlt.C_LISTPRICEACTUAL IS NULL
             OR m.C_LENGTH IS NULL
             OR m.C_WIDTH IS NULL
             OR m.C_HEIGHT IS NULL
             OR (m.C_LENGTH * m.C_WIDTH * m.C_HEIGHT) = 0
        THEN i.C_NEWCOSTPRICE

        ELSE
            (
                (
                    CEILING((PPAlt.C_LISTPRICEACTUAL / @exRate) * 100) / 100.0
                    +
                    (((m.C_LENGTH * m.C_WIDTH * m.C_HEIGHT) / 1000000000) / 66 * 6000)
                )
                *
                (1 + ISNULL(comc.C_D_RATE, 0) / 100.0)
            )
    END
    AS DECIMAL(18,2)
) AS [Calculated Landed]

--,CASE
--    WHEN i.C_NEWCOSTPRICE IS NULL OR i.C_NEWCOSTPRICE = 0
--        THEN 'ERROR - Avg Cost Missing'

--    WHEN CUR.C_CODE = 'USD'
--         AND PPAlt.C_LISTPRICEACTUAL IS NOT NULL
--         AND PPAlt.C_LISTPRICEACTUAL <> 0
--         AND m.C_LENGTH IS NOT NULL
--         AND m.C_WIDTH IS NOT NULL
--         AND m.C_HEIGHT IS NOT NULL
--         AND (m.C_LENGTH * m.C_WIDTH * m.C_HEIGHT) <> 0
--        THEN 'USD Price + CBM Freight + Duty'

--    WHEN s.C_CODE IN ('995100', '917700')
--        THEN 'Avg Cost + Duty - Supplier ' + ISNULL(s.C_CODE, 'Missing')

--    WHEN CUR.C_CODE <> 'USD'
--         OR PPAlt.C_LISTPRICEACTUAL IS NULL
--         OR PPAlt.C_LISTPRICEACTUAL = 0
--        THEN 'Avg Cost + Duty - Supplier ' + ISNULL(s.C_CODE, 'Missing')

--    WHEN m.C_LENGTH IS NULL
--         OR m.C_WIDTH IS NULL
--         OR m.C_HEIGHT IS NULL
--         OR (m.C_LENGTH * m.C_WIDTH * m.C_HEIGHT) = 0
--        THEN 'Avg Cost - CBM Missing'

--    ELSE 'Avg Cost'
--END AS [Landed Cost New Source]


,CAST(
    CASE
        WHEN i.C_NEWCOSTPRICE IS NULL OR i.C_NEWCOSTPRICE = 0
            THEN 0

        -- USD price + CBM available
        WHEN CUR.C_CODE = 'USD'
             AND PPAlt.C_LISTPRICEACTUAL IS NOT NULL
             AND PPAlt.C_LISTPRICEACTUAL <> 0
             AND m.C_LENGTH IS NOT NULL
             AND m.C_WIDTH IS NOT NULL
             AND m.C_HEIGHT IS NOT NULL
             AND (m.C_LENGTH * m.C_WIDTH * m.C_HEIGHT) <> 0
        THEN
            CASE
                WHEN i.C_NEWCOSTPRICE >
                    (
                        (
                            CEILING((PPAlt.C_LISTPRICEACTUAL / @exRate) * 100) / 100.0
                            +
                            (((m.C_LENGTH * m.C_WIDTH * m.C_HEIGHT) / 1000000000) / 66 * 6000)
                        )
                        * (1 + ISNULL(comc.C_D_RATE, 0) / 100.0)
                    )
                THEN i.C_NEWCOSTPRICE

                ELSE
                    (
                        (
                            CEILING((PPAlt.C_LISTPRICEACTUAL / @exRate) * 100) / 100.0
                            +
                            (((m.C_LENGTH * m.C_WIDTH * m.C_HEIGHT) / 1000000000) / 66 * 6000)
                        )
                        * (1 + ISNULL(comc.C_D_RATE, 0) / 100.0)
                    )
            END

        -- No USD price / no usable landed cost
        ELSE i.C_NEWCOSTPRICE

    END
    AS DECIMAL(18,2)
) AS [Landed Cost Max]


,CAST(
    i.C_NEWCOSTPRICE -
    (
        CASE
            WHEN CUR.C_CODE <> 'USD'
                 OR PPAlt.C_LISTPRICEACTUAL IS NULL
                 OR m.C_LENGTH IS NULL
                 OR m.C_WIDTH IS NULL
                 OR m.C_HEIGHT IS NULL
                 OR (m.C_LENGTH * m.C_WIDTH * m.C_HEIGHT) = 0
            THEN i.C_NEWCOSTPRICE

            ELSE
                (
                    CEILING((PPAlt.C_LISTPRICEACTUAL / @exRate) * 100) / 100.0
                    +
                    (((m.C_LENGTH * m.C_WIDTH * m.C_HEIGHT) / 1000000000) / 66 * 6000)
                )
                * (1 + ISNULL(comc.C_D_RATE, 0) / 100.0)
        END
    )
    AS DECIMAL(18,2)
) AS [Avg Cost vs Landed Cost]


,CASE 
    WHEN
        (
            CASE
                WHEN CUR.C_CODE <> 'USD'
                     OR PPAlt.C_LISTPRICEACTUAL IS NULL
                     OR m.C_LENGTH IS NULL
                     OR m.C_WIDTH IS NULL
                     OR m.C_HEIGHT IS NULL
                     OR (m.C_LENGTH * m.C_WIDTH * m.C_HEIGHT) = 0
                THEN i.C_NEWCOSTPRICE

                ELSE
                    (
                        CEILING((PPAlt.C_LISTPRICEACTUAL / @exRate) * 100) / 100.0
                        +
                        (((m.C_LENGTH * m.C_WIDTH * m.C_HEIGHT) / 1000000000) / 66 * 6000)
                    )
                    * (1 + ISNULL(comc.C_D_RATE, 0) / 100.0)
            END
        ) = 0
    THEN 'Error'

    WHEN i.C_NEWCOSTPRICE >=
        (
            CASE
                WHEN CUR.C_CODE <> 'USD'
                     OR PPAlt.C_LISTPRICEACTUAL IS NULL
                     OR m.C_LENGTH IS NULL
                     OR m.C_WIDTH IS NULL
                     OR m.C_HEIGHT IS NULL
                     OR (m.C_LENGTH * m.C_WIDTH * m.C_HEIGHT) = 0
                THEN i.C_NEWCOSTPRICE

                ELSE
                    (
                        CEILING((PPAlt.C_LISTPRICEACTUAL / @exRate) * 100) / 100.0
                        +
                        (((m.C_LENGTH * m.C_WIDTH * m.C_HEIGHT) / 1000000000) / 66 * 6000)
                    )
                    * (1 + ISNULL(comc.C_D_RATE, 0) / 100.0)
            END
        )
    THEN 'Yes'

    ELSE 'No'
END AS [Avg Cost Above Landed Cost]
-------------------------------------
,CASE
    -- 4 missing
    WHEN (CUR.C_CODE <> 'USD' OR PPAlt.C_LISTPRICEACTUAL IS NULL OR PPAlt.C_LISTPRICEACTUAL = 0)
         AND (m.C_LENGTH IS NULL OR m.C_WIDTH IS NULL OR m.C_HEIGHT IS NULL
              OR (m.C_LENGTH * m.C_WIDTH * m.C_HEIGHT) = 0)
         AND (i.C_NEWCOSTPRICE IS NULL OR i.C_NEWCOSTPRICE = 0)
         AND comc.C_ID IS NULL
        THEN 'USD Price, CBM, Avg Cost & Duty Code Missing'

    -- 3 missing
    WHEN (CUR.C_CODE <> 'USD' OR PPAlt.C_LISTPRICEACTUAL IS NULL OR PPAlt.C_LISTPRICEACTUAL = 0)
         AND (m.C_LENGTH IS NULL OR m.C_WIDTH IS NULL OR m.C_HEIGHT IS NULL
              OR (m.C_LENGTH * m.C_WIDTH * m.C_HEIGHT) = 0)
         AND (i.C_NEWCOSTPRICE IS NULL OR i.C_NEWCOSTPRICE = 0)
        THEN 'USD Price, CBM & Avg Cost Missing'

    WHEN (CUR.C_CODE <> 'USD' OR PPAlt.C_LISTPRICEACTUAL IS NULL OR PPAlt.C_LISTPRICEACTUAL = 0)
         AND (m.C_LENGTH IS NULL OR m.C_WIDTH IS NULL OR m.C_HEIGHT IS NULL
              OR (m.C_LENGTH * m.C_WIDTH * m.C_HEIGHT) = 0)
         AND comc.C_ID IS NULL
        THEN 'USD Price, CBM & Duty Code Missing'

    WHEN (CUR.C_CODE <> 'USD' OR PPAlt.C_LISTPRICEACTUAL IS NULL OR PPAlt.C_LISTPRICEACTUAL = 0)
         AND (i.C_NEWCOSTPRICE IS NULL OR i.C_NEWCOSTPRICE = 0)
         AND comc.C_ID IS NULL
        THEN 'USD Price, Avg Cost & Duty Code Missing'

    WHEN (m.C_LENGTH IS NULL OR m.C_WIDTH IS NULL OR m.C_HEIGHT IS NULL
          OR (m.C_LENGTH * m.C_WIDTH * m.C_HEIGHT) = 0)
         AND (i.C_NEWCOSTPRICE IS NULL OR i.C_NEWCOSTPRICE = 0)
         AND comc.C_ID IS NULL
        THEN 'CBM, Avg Cost & Duty Code Missing'

    -- 2 missing
    WHEN (CUR.C_CODE <> 'USD' OR PPAlt.C_LISTPRICEACTUAL IS NULL OR PPAlt.C_LISTPRICEACTUAL = 0)
         AND (m.C_LENGTH IS NULL OR m.C_WIDTH IS NULL OR m.C_HEIGHT IS NULL
              OR (m.C_LENGTH * m.C_WIDTH * m.C_HEIGHT) = 0)
        THEN 'USD Price & CBM Missing'

    WHEN (CUR.C_CODE <> 'USD' OR PPAlt.C_LISTPRICEACTUAL IS NULL OR PPAlt.C_LISTPRICEACTUAL = 0)
         AND (i.C_NEWCOSTPRICE IS NULL OR i.C_NEWCOSTPRICE = 0)
        THEN 'USD Price & Avg Cost Missing'

    WHEN (CUR.C_CODE <> 'USD' OR PPAlt.C_LISTPRICEACTUAL IS NULL OR PPAlt.C_LISTPRICEACTUAL = 0)
         AND comc.C_ID IS NULL
        THEN 'USD Price & Duty Code Missing'

    WHEN (m.C_LENGTH IS NULL OR m.C_WIDTH IS NULL OR m.C_HEIGHT IS NULL
          OR (m.C_LENGTH * m.C_WIDTH * m.C_HEIGHT) = 0)
         AND (i.C_NEWCOSTPRICE IS NULL OR i.C_NEWCOSTPRICE = 0)
        THEN 'CBM & Avg Cost Missing'

    WHEN (m.C_LENGTH IS NULL OR m.C_WIDTH IS NULL OR m.C_HEIGHT IS NULL
          OR (m.C_LENGTH * m.C_WIDTH * m.C_HEIGHT) = 0)
         AND comc.C_ID IS NULL
        THEN 'CBM & Duty Code Missing'

    WHEN (i.C_NEWCOSTPRICE IS NULL OR i.C_NEWCOSTPRICE = 0)
         AND comc.C_ID IS NULL
        THEN 'Avg Cost & Duty Code Missing'

    -- 1 missing
    WHEN CUR.C_CODE <> 'USD'
         OR PPAlt.C_LISTPRICEACTUAL IS NULL
         OR PPAlt.C_LISTPRICEACTUAL = 0
        THEN 'USD Price Missing'

    WHEN m.C_LENGTH IS NULL
         OR m.C_WIDTH IS NULL
         OR m.C_HEIGHT IS NULL
         OR (m.C_LENGTH * m.C_WIDTH * m.C_HEIGHT) = 0
        THEN 'CBM Missing'

    WHEN i.C_NEWCOSTPRICE IS NULL
         OR i.C_NEWCOSTPRICE = 0
        THEN 'Avg Cost Missing'

    WHEN comc.C_ID IS NULL
        THEN 'Duty Code Missing'

    ELSE ''
END AS [Landed Cost Missing]

------------------


FROM [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCT] p WITH (NOLOCK)

LEFT JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCT_STATISTICS] pstats WITH (NOLOCK)
    ON pstats.C_ID = p.C_STATISTICS

LEFT JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCT_PURCHASING] pp WITH (NOLOCK)
    ON pp.C_ID = p.C_PURCHASING

LEFT JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_SUPPLIER] s WITH (NOLOCK)
    ON s.C_ID = pp.C_DEFAULTSUPPLIER

LEFT JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCTDEPARTMENT] PD WITH (NOLOCK)
    ON PD.C_ID = p.C_DEPARTMENT

LEFT JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCTDEPARTMENTGROUP] PDG WITH (NOLOCK)
    ON PD.C_GROUP = PDG.C_ID

LEFT JOIN SalesYTD Ytd
    ON Ytd.Product_ID = p.C_ID

LEFT JOIN ForecastOrders FO
    ON FO.Product_ID = p.C_ID

LEFT JOIN SupplierPurchasingYTD SPY
    ON SPY.Product_ID = p.C_ID

LEFT JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCT_COSTINGS] cc WITH (NOLOCK)
    ON cc.C_ID = p.C_COSTINGS

LEFT JOIN IQAvgCost i
    ON i.C_PRODUCT = p.C_ID
    AND i.C_BRANCH = 4337992263053
left outer join T_PRODUCT_MEASUREMENTS m  WITH (NOLOCK) on p.C_MEASUREMENTS = m.c_id 

LEFT JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCT_ALTERNATEPURCHASINGINFO] PI  WITH (NOLOCK)
    ON PI.C__OWNER_ = p.C_ID

LEFT JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCT_PURCHASING] PPAlt  WITH (NOLOCK)
    ON PPAlt.C_ID = PI.C_ID

LEFT JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_CURRENCY] CURAlt  WITH (NOLOCK)
    ON CURAlt.C_ID = PPAlt.C_LISTPRICECURRENCY

LEFT JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_CURRENCY] CUR  WITH (NOLOCK) ON Cur.C_ID = PPalt.[C_LISTPRICECURRENCY]

left outer join T_PRODUCT_IMPORTDUTYSETTINGS com with (nolock) on com.C_ID = p.C_IMPORTDUTYSETTINGS
left outer join T_IS_COMMODITYCODE comc on comc.C_ID = com.C_COMMODITYCODE

WHERE 
    p.C_TYPE NOT IN (15, 2, 6, 19, 10, 18)
    AND PDG.C_CODE = 'AQUAI'
    AND p.C_CODE = '11114355';


  -- select * from T_PRODUCT_IMPORTDUTYSETTINGS