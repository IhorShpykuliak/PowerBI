SELECT 
    -- Primary & Foreign Keys for Star Schema Relationships
    PO.C_ID                                AS PurchaseOrderID,
    POL.C_ID                               AS POLineID,
    CAST(PO.C_DATE AS DATE)                AS PODateKey,        -- Foreign key to Dim_Date
    PO.C_SUPPLIER                          AS SupplierID,       -- Foreign key to Dim_Supplier / Dim_Customer
    POL.C_PRODUCT                          AS ProductID,        -- Foreign key to Dim_Product
    PO.C_WORKFLOWSTATUS                    AS StatusID,         -- Foreign key to Dim_Status (if applicable)
    
    -- Purchase Order Header Attributes
    PO.C_NUMBER                            AS PONumber,
    
    -- Line Quantities
    ISNULL(POL.C_QUANTITY, 0)              AS QtyOrdered,
    ISNULL(POL.C_QUANTITYSUPPLIED, 0)      AS QtySupplied,
    ISNULL(POL.C_QUANTITYOUTSTANDING, 0)   AS QtyOutstanding,
    ISNULL(POL.C_QUANTITYWRITTENOFF, 0)    AS QtyWrittenOff,
    ISNULL(POL.C_PACKQUANTITY, 0)          AS PackQuantity,
    
    -- Line Amounts
    ISNULL(POL.C_NETAMOUNTLESSDISCOUNTBASE, 0) AS NetAmount,
    
    -- Calculated Financial Metrics (Outstanding Amount)
    CASE 
        WHEN ISNULL(POL.C_QUANTITY, 0) > 0 
        THEN (ISNULL(POL.C_NETAMOUNTLESSDISCOUNTBASE, 0) / POL.C_QUANTITY) * ISNULL(POL.C_QUANTITYOUTSTANDING, 0)
        ELSE 0 
    END                                    AS OutstandingAmount

FROM [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PURCHASEORDER] PO WITH (NOLOCK)
INNER JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PURCHASEORDER_LINE] POL WITH (NOLOCK)
    ON POL.C__OWNER_ = PO.C_ID
INNER JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCT] P WITH (NOLOCK)
    ON P.C_ID = POL.C_PRODUCT
INNER JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCTDEPARTMENT] PD WITH (NOLOCK)
    ON PD.C_ID = P.C_DEPARTMENT
INNER JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCTDEPARTMENTGROUP] PDG WITH (NOLOCK)
    ON PD.C_GROUP = PDG.C_ID
WHERE 1=1 
    AND PDG.C_CODE = 'AQUAI'
    AND P.C_ID != 21479144630299 -- Exclude system/text item 'TEXT HAS DEPARTMENT GROUP AQUA I'
    AND PO.C_DATE >= '2026-01-01'