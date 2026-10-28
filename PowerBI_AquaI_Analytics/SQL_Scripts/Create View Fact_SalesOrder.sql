 /*******************************************************************************
   Fact_SalesOrder:  
*******************************************************************************/
Use [Tippers];
GO
 IF OBJECT_ID('dbo.Fact_SalesOrder', 'V') IS NOT NULL
     DROP VIEW dbo.Fact_SalesOrder;
 GO

 CREATE VIEW dbo.Fact_SalesOrder AS
SELECT
    COALESCE(KC.C_PRODUCT, P.C_ID) AS ProductID,
    COALESCE(KP.C_CODE, P.C_CODE) AS C_CODE,
    COALESCE(KP.C_DESCRIPTION, P.C_DESCRIPTION) AS C_DESCRIPTION,
    CASE
        WHEN P.C_TYPE = 3 THEN 'Yes'
        ELSE 'No'
    END AS IsKit,
    SO.C_ID AS SalesOrderID,
    LTRIM(RTRIM(SO.C_NUMBER)) AS OrderNumber,
    CAST(SO.C_DATE AS DATE) AS SODateKey,
    SO.C_CUSTOMER AS CustomerID,
    SO.C_BRANCH AS BranchID,
    SO.C_SALESREP AS SalesRepID,
    SO.C_SOURCEFORECASTORDER AS ForecastOrder,
    SO.C_ORDERTYPE AS OrderTypeID,
    SO.C_WORKFLOWSTATUS AS WorkflowStatusID,
    ISNULL(SOL.C_QUANTITY, 0) * ISNULL(KC.C_QUANTITY, 1) AS QuantityOrdered,
    ISNULL(SOL.C_QUANTITYOUTSTANDING, 0) * ISNULL(KC.C_QUANTITY, 1) AS QuantityOutstanding,
    ISNULL(SOL.C_NETAMOUNT, 0) AS LineNetAmount,
    COALESCE(SOL.C_DUEDATE, SO.C_DUEDATE) AS EffectiveDueDate

FROM [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_SALESORDER] SO WITH (NOLOCK)
    INNER JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_SALESORDER_LINE] SOL WITH (NOLOCK)
        ON SOL.C__OWNER_ = SO.C_ID
    INNER JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCT] P WITH (NOLOCK)
        ON P.C_ID = SOL.C_PRODUCT

    OUTER APPLY
    (
        SELECT
            K.C_PRODUCT,
            K.C_QUANTITY
        FROM [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCT_KITCOMPONENT] K
        WHERE K.C__OWNER_ = P.C_ID
        AND P.C_TYPE = 3
    
        UNION ALL
    
        SELECT P.C_ID, 1.0
        WHERE P.C_TYPE <> 3

    ) KC
    LEFT JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCT] KP WITH (NOLOCK)
       ON KP.C_ID = KC.C_PRODUCT
    LEFT JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCTDEPARTMENT] PD WITH (NOLOCK)
        ON PD.C_ID = P.C_DEPARTMENT
    LEFT JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCTDEPARTMENTGROUP] PDG WITH (NOLOCK)
        ON PD.C_GROUP = PDG.C_ID
    WHERE 1=1
    AND PDG.C_CODE = 'AQUAI';
    -- AND SO.C_NUMBER = 'Ai--SO0000822';

 GO








-- SELECT
--     SOL.C_PRODUCT                                AS ProductID,
--     SOL.C_ID                                     AS SalesOrderLineID,
--     SO.C_ID                                      AS SalesOrderID,
--     LTRIM(RTRIM(SO.C_NUMBER))                    AS OrderNumber,
--     CAST(SO.C_DATE AS DATE)                      AS SODateKey,
--     SO.C_CUSTOMER                                AS CustomerID,
--     SO.C_BRANCH                                  AS BranchID,
--     SO.C_SALESREP                                AS SalesRepID,
--     SO.C_SOURCEFORECASTORDER                     AS ForecastOrder,
--     SO.C_ORDERTYPE                               AS OrderTypeID,
--     SO.C_WORKFLOWSTATUS                          AS WorkflowStatusID,
--     CASE WHEN P.C_TYPE = 3 THEN 1 ELSE 0 END     AS IsKit,
--     ISNULL(SOL.C_QUANTITY, 0)                    AS QuantityOrdered,
--     ISNULL(SOL.C_QUANTITYOUTSTANDING, 0)         AS QuantityOutstanding,
--     ISNULL(SOL.C_NETAMOUNT, 0)                   AS LineNetAmount,
--     COALESCE(SOL.C_DUEDATE, SO.C_DUEDATE)        AS EffectiveDueDate
-- FROM [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_SALESORDER] SO WITH (NOLOCK)
-- INNER JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_SALESORDER_LINE] SOL WITH (NOLOCK)
--     ON SOL.C__OWNER_ = SO.C_ID
-- INNER JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCT] P WITH (NOLOCK)
--     ON P.C_ID = SOL.C_PRODUCT
-- INNER JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCTDEPARTMENT] PD WITH (NOLOCK)
--     ON PD.C_ID = P.C_DEPARTMENT
-- INNER JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCTDEPARTMENTGROUP] PDG WITH (NOLOCK)
--     ON PDG.C_ID = PD.C_GROUP
-- WHERE PDG.C_CODE = 'AQUAI';
-- GO