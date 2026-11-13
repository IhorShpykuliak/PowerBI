SELECT 
    PROD.[C_ID] AS [ProductID]
    ,B.C_ID AS [BranchID]
    ,SUM(PBS.[C_STOCKLEVEL]) AS [Stock Level]
    ,SUM(PBS.[C_FREESTOCKLEVEL]) AS [Free Stock Level]
  FROM [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCT] PROD 
    LEFT JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCT_COSTINGS] PC ON PC.C_ID = PROD.C_COSTINGS
    LEFT JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCTBRANCHSTATISTICS] PBS ON PBS.C_PRODUCT = PROD.C_ID
    LEFT JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_BRANCH] B ON PBS.C_BRANCH = B.C_ID
    LEFT JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCT_PURCHASING] PP ON PP.C_ID = PROD.C_PURCHASING
    LEFT JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCT_SELLING] PS ON PS.C_ID = PROD.C_SELLING
    LEFT JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCT_SELLING_PRICEDEFINITION] PSD ON PSD.[C__OWNER_]= PS.C_ID and PSD.C_DESCRIPTION = 'Retail'
    LEFT JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_SUPPLIER] S ON PP.C_DEFAULTSUPPLIER = S.C_ID
    LEFT JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCTDEPARTMENT] PD WITH (NOLOCK) ON PD.C_ID = PROD.C_DEPARTMENT
    LEFT JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCTDEPARTMENTGROUP] PDG WITH (NOLOCK) ON PD.C_GROUP = PDG.C_ID
    WHERE PBS.[C_STOCKLEVEL] > 0
      --AND PROD.[C_CODE] = '11113875'
        --S.C_CODE = '959500' 
        --AND B.C_CODE = 'LICH'
    AND PDG.C_CODE = 'AQUAI'
  Group BY PROD.[C_ID],B.C_ID
      
          