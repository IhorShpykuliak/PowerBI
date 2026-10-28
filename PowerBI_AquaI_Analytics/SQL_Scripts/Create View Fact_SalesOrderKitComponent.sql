
  /*******************************************************************************
  Fact_SalesOrderKitComponent: 
*******************************************************************************/
IF OBJECT_ID('dbo.Fact_SalesOrderKitComponent', 'V') IS NOT NULL
    DROP VIEW dbo.Fact_SalesOrderKitComponent;
GO

CREATE VIEW dbo.Fact_SalesOrderKitComponent AS
SELECT
    P.C_CODE                                     AS KitCode,
    CP.C_CODE                                    AS ComponentCode,
    CP.C_DESCRIPTION                             AS ComponentDescription,
    KIT.C_PRODUCT                                AS ComponentProductID,
    SOL.C_PRODUCT                                AS KitProductID,
    SOL.C_ID                                     AS SalesOrderLineID,
    SO.C_ID                                      AS SalesOrderID,
    LTRIM(RTRIM(SO.C_NUMBER))                    AS OrderNumber,
    CAST(SO.C_DATE AS DATE)                      AS SODateKey,
    SO.C_CUSTOMER                                AS CustomerID,
    SO.C_BRANCH                                  AS BranchID,
    SO.C_WORKFLOWSTATUS                          AS WorkflowStatusID,
    COALESCE(SOL.C_DUEDATE, SO.C_DUEDATE)        AS EffectiveDueDate,
    ISNULL(KIT.C_QUANTITY, 0)                    AS QtyPerKit,
    ISNULL(SOL.C_QUANTITY, 0) * ISNULL(KIT.C_QUANTITY, 0)             AS ComponentQtyOrdered,
    ISNULL(SOL.C_QUANTITYOUTSTANDING, 0) * ISNULL(KIT.C_QUANTITY, 0)  AS ComponentQtyOutstanding
FROM [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_SALESORDER_LINE] SOL WITH (NOLOCK)
INNER JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_SALESORDER] SO WITH (NOLOCK)
    ON SO.C_ID = SOL.C__OWNER_
INNER JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCT] P WITH (NOLOCK)
    ON P.C_ID = SOL.C_PRODUCT AND P.C_TYPE = 3
INNER JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCT_KITCOMPONENT] KIT WITH (NOLOCK)
    ON KIT.C__OWNER_ = P.C_ID
INNER JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCT] CP WITH (NOLOCK)
    ON CP.C_ID = KIT.C_PRODUCT
INNER JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCTDEPARTMENT] PD WITH (NOLOCK)
    ON PD.C_ID = CP.C_DEPARTMENT
INNER JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCTDEPARTMENTGROUP] PDG WITH (NOLOCK)
    ON PDG.C_ID = PD.C_GROUP
WHERE PDG.C_CODE = 'AQUAI';
GO