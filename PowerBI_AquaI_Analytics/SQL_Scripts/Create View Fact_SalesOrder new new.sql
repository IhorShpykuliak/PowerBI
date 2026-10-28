/*******************************************************************************
  Script Name:  Create_Fact_SalesOrder.sql
  Description:  Single fact view for customer Sales Orders (AQUAI only), built to
                feed the "Forecast Ordering Sheet" (one row per product, rolling
                12-month columns).

  Grain:        1 row = 1 Sales Order line x 1 resolved product
                - Standard product  -> 1 row  (ProductID = the product itself, QtyPerUnit = 1)
                - Kit (C_TYPE = 3)  -> N rows (one per kit component, QtyPerUnit = recipe qty)
                - Kit with NO components is kept as a single row (never silently dropped)

  Why one view:
                ProductID always points to the product that must actually be
                ordered from the supplier (the component for kits), so a single
                relationship Dim_Product[ProductID] -> Fact_SalesOrder[ProductID]
                drives every column of the Excel sheet.

  Double-counting protection:
                Header/line-level values (line qty, line net amount) are repeated
                on every exploded row, so they are exposed ONLY on the first row of
                each order line (IsFirstRowOfLine = 1) and are 0 on the others.
                SUM() on those columns is therefore always safe.

  Excel mapping:
                "Forecast Orders Outstanding" (cols V / AC / ...)
                  -> SUM(QuantityOutstanding) filtered to Order Type "7. Forecast Order",
                     split by month using DueMonthOffset / DueMonthLabel.
                  Due date rule from the sheet: sales order LINE due date, and if it
                  is NULL fall back to the order HEADER due date (EffectiveDueDate).

  Filters:      AQUAI only, orders dated 2026-01-01 or later, no DELIVERY CHARGE / TEXT items.

  Database:     Tippers
  Author:       Ihor Shpykuliak
*******************************************************************************/

USE [Tippers];
GO

-- Drop the view if it already exists so the script can be re-run safely
IF OBJECT_ID('dbo.Fact_SalesOrder', 'V') IS NOT NULL
    DROP VIEW dbo.Fact_SalesOrder;
GO

CREATE VIEW dbo.Fact_SalesOrder AS
WITH Src AS
(
    SELECT
        -- What the customer actually ordered (the kit itself, or the standard product)
        SOL.C_PRODUCT                                  AS OrderedProductID,
        P.C_CODE                                       AS OrderedProductCode,
        P.C_DESCRIPTION                                AS OrderedProductDescription,
        CASE WHEN P.C_TYPE = 3 THEN 1 ELSE 0 END       AS IsKit,

        -- What we must order from the supplier (kit component, or the product itself)
        -- -> relationship key to Dim_Product[ProductID]
        R.ResolvedProductID                            AS ProductID,

        -- Components needed per 1 ordered unit (recipe quantity for kits, 1 for standard items)
        CASE WHEN R.ResolvedProductID <> P.C_ID
             THEN ISNULL(KIT.C_QUANTITY, 0)
             ELSE 1.0 END                              AS QtyPerUnit,

        -- Document keys
        SOL.C_ID                                       AS SalesOrderLineID,
        SO.C_ID                                        AS SalesOrderID,
        LTRIM(RTRIM(SO.C_NUMBER))                      AS OrderNumber,

        -- Foreign keys to conformed dimensions
        CAST(SO.C_DATE AS DATE)                        AS SODateKey,           -- -> Dim_Date[Date]
        SO.C_CUSTOMER                                  AS CustomerID,          -- -> Dim_Customer[CustomerID]
        SO.C_BRANCH                                    AS BranchID,            -- -> Dim_Branch[BranchID]
        SO.C_SALESREP                                  AS SalesRepID,          -- -> Dim_SalesRep[SalesRepID]
        SO.C_SOURCEFORECASTORDER                       AS ForecastOrder,       -- source Forecast Order reference
        SO.C_ORDERTYPE                                 AS OrderTypeID,         -- -> Dim_OrderType (filter "7. Forecast Order")
        SO.C_WORKFLOWSTATUS                            AS WorkflowStatusID,

        -- Due date rule: order LINE due date first, order HEADER due date as fallback
        CAST(COALESCE(SOL.C_DUEDATE, SO.C_DUEDATE) AS DATE) AS EffectiveDueDate,

        -- Line-level values (before kit explosion)
        ISNULL(SOL.C_QUANTITY, 0)                      AS LineQty,
        ISNULL(SOL.C_QUANTITYOUTSTANDING, 0)           AS LineQtyOutstanding,
        ISNULL(SOL.C_NETAMOUNT, 0)                     AS LineNet
    FROM [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_SALESORDER_LINE] SOL WITH (NOLOCK)
    INNER JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_SALESORDER] SO WITH (NOLOCK)
        ON SO.C_ID = SOL.C__OWNER_
    INNER JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCT] P WITH (NOLOCK)
        ON P.C_ID = SOL.C_PRODUCT

    -- Kit explosion: only kits (type 3) join to their components; standard products get NULL here.
    -- A plain LEFT JOIN lets the optimizer use hash/merge joins (much faster than OUTER APPLY + UNION ALL).
    LEFT JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCT_KITCOMPONENT] KIT WITH (NOLOCK)
        ON KIT.C__OWNER_ = P.C_ID
       AND P.C_TYPE = 3

    -- Resolve the product to order once: kit component if present, otherwise the product itself
    CROSS APPLY (
        SELECT CASE WHEN P.C_TYPE = 3 AND KIT.C_PRODUCT IS NOT NULL
                    THEN KIT.C_PRODUCT
                    ELSE P.C_ID END AS ResolvedProductID
    ) R

    -- Department group of the RESOLVED product (component for kits) -> AQUAI filter
    INNER JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCT] RP WITH (NOLOCK)
        ON RP.C_ID = R.ResolvedProductID
    INNER JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCTDEPARTMENT] PD WITH (NOLOCK)
        ON PD.C_ID = RP.C_DEPARTMENT
    INNER JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCTDEPARTMENTGROUP] PDG WITH (NOLOCK)
        ON PDG.C_ID = PD.C_GROUP
    WHERE PDG.C_CODE = 'AQUAI'
      -- Only orders from 2026 onwards (performance). Change the date here if needed.
      AND SO.C_DATE >= '2026-01-01'
      -- Exclude non-stock items: delivery charges and TEXT lines
      AND UPPER(RP.C_CODE) NOT LIKE '%DELIVERY%'
      AND UPPER(ISNULL(RP.C_DESCRIPTION, '')) NOT LIKE '%DELIVERY CHARGE%'
      AND UPPER(RP.C_CODE) <> 'TEXT'
      AND UPPER(ISNULL(RP.C_DESCRIPTION, '')) NOT LIKE 'TEXT%'
      AND RP.C_ID <> 21479144630299                -- system/text item 'TEXT HAS DEPARTMENT GROUP AQUA I'
      -- To filter by the department of the KIT itself instead of its components,
      -- change "RP.C_DEPARTMENT" to "P.C_DEPARTMENT" in the PD join above.
),
Ranked AS
(
    -- Number the exploded rows inside each order line; row 1 carries the line-level values
    SELECT
        Src.*,
        ROW_NUMBER() OVER (PARTITION BY SalesOrderLineID ORDER BY ProductID) AS rn
    FROM Src
)
SELECT
    -- Keys
    ProductID,                                   -- product to order (component / standard) -> Dim_Product[ProductID]
    OrderedProductID,                            -- what the customer ordered (kit or standard product)
    OrderedProductCode,
    OrderedProductDescription,
    IsKit,                                       -- 1 = row comes from a kit explosion
    SalesOrderLineID,
    SalesOrderID,
    OrderNumber,
    SODateKey,
    CustomerID,
    BranchID,
    SalesRepID,
    ForecastOrder,
    OrderTypeID,
    WorkflowStatusID,

    -- Due date and month bucketing for the rolling 12-month columns of the sheet
    EffectiveDueDate,
    DATEFROMPARTS(YEAR(EffectiveDueDate), MONTH(EffectiveDueDate), 1)       AS DueMonthStart,   -- first day of due month
    CONVERT(CHAR(7), EffectiveDueDate, 126)                                 AS DueMonthLabel,   -- 'YYYY-MM' column header
    DATEDIFF(MONTH, GETDATE(), EffectiveDueDate)                            AS DueMonthOffset,  -- 0 = current month, 1 = next month ... (negative = overdue)

    -- Components needed per 1 ordered unit (1 for standard products)
    QtyPerUnit,

    -- Quantities at RESOLVED PRODUCT level (what must be ordered) - safe to SUM on every row
    LineQty            * QtyPerUnit              AS QuantityOrdered,
    LineQtyOutstanding * QtyPerUnit              AS QuantityOutstanding,

    -- Line-level values: populated on the first row of each order line only (no double counting)
    CASE WHEN rn = 1 THEN 1 ELSE 0 END           AS IsFirstRowOfLine,
    CASE WHEN rn = 1 THEN LineQty            ELSE 0 END AS LineQtyOrdered,
    CASE WHEN rn = 1 THEN LineQtyOutstanding ELSE 0 END AS LineQtyOutstandingOnly,
    CASE WHEN rn = 1 THEN LineNet            ELSE 0 END AS LineNetAmount
FROM Ranked;
GO
