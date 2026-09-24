SELECT 
    ppa.C_ID AS AlternatePurchasingID,
    ppa.C__OWNER_ AS ProductID, -- Foreign Key to Dim_Product
    s2.C_CODE AS AltSupplierCode,
    s2.C_NAME AS AltSupplierName,
    pp2.C_SUPPLIERPRODUCTCODE AS AltSupplierProductCode,
    CAST(pp2.C_LISTPRICEACTUAL AS DECIMAL(18,2)) AS AltListPriceActual,
    cur2.C_CODE AS AltCurrencyCode,
    CAST(
        CASE 
            WHEN cur2.C_CODE = 'USD' THEN pp2.C_LISTPRICEACTUAL 
            ELSE 0 
        END AS DECIMAL(18,2)
    ) AS AltUSDListPrice

FROM [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCT_ALTERNATEPURCHASINGINFO] ppa WITH (NOLOCK)
INNER JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCT_PURCHASING] pp2 WITH (NOLOCK) 
    ON pp2.C_ID = ppa.C_ID
LEFT JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_SUPPLIER] s2 WITH (NOLOCK) 
    ON s2.C_ID = pp2.C_DEFAULTSUPPLIER
LEFT JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_CURRENCY] cur2 WITH (NOLOCK) 
    ON cur2.C_ID = pp2.C_LISTPRICECURRENCY

-- Ограничиваем выборку только товарами из группы AQUAI:
INNER JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCT] p WITH (NOLOCK) 
    ON p.C_ID = ppa.C__OWNER_
INNER JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCTDEPARTMENT] PD WITH (NOLOCK) 
    ON PD.C_ID = p.C_DEPARTMENT
INNER JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCTDEPARTMENTGROUP] PDG WITH (NOLOCK) 
    ON PDG.C_ID = PD.C_GROUP

WHERE ppa.C_ID IS NOT NULL
  AND p.C_TYPE NOT IN (15, 2, 6, 19, 10, 18)
  AND PDG.C_CODE = 'AQUAI';