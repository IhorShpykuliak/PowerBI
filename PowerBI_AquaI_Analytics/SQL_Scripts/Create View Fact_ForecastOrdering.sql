
/*******************************************************************************
  PART 2 of 2
  Script Name:  Fact_ForecastOrdering
  Description:  Calculates the whole "Forecast Ordering Sheet" in SQL.
                One row per PRODUCT x MONTH (MonthOffset 0 = current month ... 12),
                so a Power BI matrix (products in rows, MonthLabel in columns)
                reproduces the Excel layout exactly.

  Calculation logic (taken from the "Notes" rows of the Excel template):
    Ideal Stocking Level      = Monthly Average Sales * Required Months Stock
    Forecasted Sales          = (Monthly Average Sales * Growth Factor) + Forecast Orders Outstanding
    Months Stock Remaining    = (Stock - Forecast Orders Outstanding) / Monthly Average Sales
    Suggested Order Amount    = Ideal - (Stock + Ordered Stock - Forecasted Sales)
                                If result <= 0 or < MOQ -> 0, else rounded UP to a full Carton Quantity
    Effective Order           = Manual Order Amount if entered, otherwise Suggested Order Amount
    Predicted Stock (month m) = Predicted Stock (m-1) - Forecasted Sales (m-1)
                                + Ordered Stock (m-1) + Effective Order (m-1)
                                (month 0 = current stock; an order placed in month m lands in month m+1)
    Container Value           = Effective Order * Supplier Cost
    Space Required For Order  = Effective Order * CBM

  Performance design:
    Every heavy source (sales history, forecast orders, purchase orders, USD supplier)
    is read exactly ONCE and pivoted into one row per product (FO0..FO12, PO0..PO12,
    MAN0..MAN12). The month-by-month chain is a recursive CTE that only does scalar
    math on those columns - it has no joins, so nothing is re-read per month.

  Filters:  AQUAI products only, orders / purchase orders dated 2026-01-01 or later,
            DELIVERY CHARGE and TEXT items excluded, only outstanding quantities.

  ----------------------------- ASSUMPTIONS TO VERIFY -----------------------------
   1. [T_SALESORDERTYPE] is the Order Type lookup table behind "Dim_OrderType"
      (column C_DESCRIPTION = '7. Forecast Order'). If you get "Invalid object name",
      take the table name from the Power Query source of Dim_OrderType and replace
      it in CTE ForecastType.
   2. Purchase order due date = T_PURCHASEORDER_LINE.C_DUEDATE, falling back to
      T_PURCHASEORDER.C_DUEDATE (CTE PoOrdered). Rename if the columns differ.
   3. Sales analysis Quantity is already signed (credit notes are negative).
   4. Growth Factor field C_D_PERCENTAGEGROWTH is used as a multiplier
      (0 / NULL -> 1, i.e. no growth). Change CTE Prod if it is stored as a percent.
   5. CBM uses C_LENGTH * C_WIDTH * C_HEIGHT (same as Dim_Product). The Excel
      mentions D_PackLength/Width/Height - swap them in CTE Prod if they exist.
   6. Required Months Stock values in CTE Cfg are PLACEHOLDERS - confirm with Joe.
   7. Overdue Forecast Orders / Purchase Orders (due date before this month) are
      counted in the CURRENT month. Anything due after month +12 is ignored.
   8. Monthly Average Sales = last 6 COMPLETE calendar months / 6.
   9. DELIVERY CHARGE / TEXT items are recognised by code/description patterns
      (see WHERE in CTE Prod). Adjust the patterns if other items slip through.
  ---------------------------------------------------------------------------------

  Run order: PART 1 (Fact_SalesOrder) must exist first - this view reads from it.
  Database:  Tippers
*******************************************************************************/

-- Optional manual overrides for the "Manual Order amount" columns.
-- Insert rows here (ProductID + first day of the month + quantity); the view uses
-- them instead of the Suggested Order Amount and carries them into Predicted Stock.
IF OBJECT_ID('dbo.ForecastOrdering_ManualOrder', 'U') IS NULL
    CREATE TABLE dbo.ForecastOrdering_ManualOrder (
        ProductID   BIGINT         NOT NULL,   -- Dim_Product[ProductID]
        OrderMonth  DATE           NOT NULL,   -- first day of the month, e.g. '2026-11-01'
        ManualQty   DECIMAL(19,4)  NOT NULL,
        CONSTRAINT PK_ForecastOrdering_ManualOrder PRIMARY KEY (ProductID, OrderMonth)
    );
GO

IF OBJECT_ID('dbo.Fact_ForecastOrdering', 'V') IS NOT NULL
    DROP VIEW dbo.Fact_ForecastOrdering;
GO

CREATE VIEW dbo.Fact_ForecastOrdering AS
WITH
-- ---------------------------------------------------------------------------
-- Configuration
-- ---------------------------------------------------------------------------
Cfg AS
(
    SELECT
        CAST(3 AS DECIMAL(9,2))                                   AS CoreMonths,      -- PLACEHOLDER: months of stock for Core products
        CAST(2 AS DECIMAL(9,2))                                   AS NonCoreMonths,   -- PLACEHOLDER: months of stock for non-Core products
        DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1)       AS CurrentMonthStart
),
-- Order Type id of "7. Forecast Order"
ForecastType AS
(
    SELECT C_ID
    FROM [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_SALESORDERTYPE] WITH (NOLOCK)
    WHERE LTRIM(RTRIM(C_DESCRIPTION)) = '7. Forecast Order'
),
-- Sales orders that were created FROM a forecast order (excluded from average sales)
ForecastCreatedSO AS
(
    SELECT DISTINCT LTRIM(RTRIM(SO.C_NUMBER)) AS OrderNumber
    FROM [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_SALESORDER] SO WITH (NOLOCK)
    WHERE SO.C_SOURCEFORECASTORDER IS NOT NULL
      AND SO.C_SOURCEFORECASTORDER <> 0
),
-- ---------------------------------------------------------------------------
-- Monthly Average Sales: last 6 complete months, whole company,
-- invoices minus credits (signed quantity), excluding forecast-created orders
-- ---------------------------------------------------------------------------
AvgSales AS
(
    SELECT
        SA.[Product_ID]                                         AS ProductID,
        SUM(SA.[Quantity]) / 6.0                                AS MonthlyAvgSales
    FROM [Intact_IQ_Walter_Tipper_Ltd_Archive].[dbo].[Tippers_SalesAnalysis] SA WITH (NOLOCK)
    CROSS JOIN Cfg
    LEFT JOIN ForecastCreatedSO FSO
        ON FSO.OrderNumber = LTRIM(RTRIM(SA.[Sales_Order_Number]))
    WHERE SA.[Date] >= DATEADD(MONTH, -6, Cfg.CurrentMonthStart)
      AND SA.[Date] <  Cfg.CurrentMonthStart
      AND FSO.OrderNumber IS NULL
    GROUP BY SA.[Product_ID]
),
-- ---------------------------------------------------------------------------
-- Forecast Orders Outstanding per product and month (kits already exploded
-- into components by Fact_SalesOrder; due date = line date, else header date)
-- ---------------------------------------------------------------------------
ForecastOut AS
(
    SELECT x.ProductID, x.MonthOffset, SUM(x.Qty) AS Qty
    FROM (
        SELECT
            FS.ProductID,
            CASE WHEN FS.DueMonthOffset < 0 THEN 0 ELSE FS.DueMonthOffset END AS MonthOffset,
            FS.QuantityOutstanding                                            AS Qty
        FROM dbo.Fact_SalesOrder FS
        WHERE FS.OrderTypeID IN (SELECT C_ID FROM ForecastType)
          AND FS.DueMonthOffset IS NOT NULL
          AND FS.QuantityOutstanding > 0
    ) x
    WHERE x.MonthOffset <= 12
    GROUP BY x.ProductID, x.MonthOffset
),
FOPiv AS
(
    SELECT ProductID,
        SUM(CASE WHEN MonthOffset = 0 THEN Qty ELSE 0 END) AS FO0,
        SUM(CASE WHEN MonthOffset = 1 THEN Qty ELSE 0 END) AS FO1,
        SUM(CASE WHEN MonthOffset = 2 THEN Qty ELSE 0 END) AS FO2,
        SUM(CASE WHEN MonthOffset = 3 THEN Qty ELSE 0 END) AS FO3,
        SUM(CASE WHEN MonthOffset = 4 THEN Qty ELSE 0 END) AS FO4,
        SUM(CASE WHEN MonthOffset = 5 THEN Qty ELSE 0 END) AS FO5,
        SUM(CASE WHEN MonthOffset = 6 THEN Qty ELSE 0 END) AS FO6,
        SUM(CASE WHEN MonthOffset = 7 THEN Qty ELSE 0 END) AS FO7,
        SUM(CASE WHEN MonthOffset = 8 THEN Qty ELSE 0 END) AS FO8,
        SUM(CASE WHEN MonthOffset = 9 THEN Qty ELSE 0 END) AS FO9,
        SUM(CASE WHEN MonthOffset = 10 THEN Qty ELSE 0 END) AS FO10,
        SUM(CASE WHEN MonthOffset = 11 THEN Qty ELSE 0 END) AS FO11,
        SUM(CASE WHEN MonthOffset = 12 THEN Qty ELSE 0 END) AS FO12
    FROM ForecastOut
    GROUP BY ProductID
),
-- ---------------------------------------------------------------------------
-- Ordered Stock: outstanding purchase order quantity per product and due month
-- (purchase orders dated 2026-01-01 or later)
-- ---------------------------------------------------------------------------
PoOrdered AS
(
    SELECT x.ProductID, x.MonthOffset, SUM(x.Qty) AS Qty
    FROM (
        SELECT
            POL.C_PRODUCT                                                     AS ProductID,
            CASE WHEN DATEDIFF(MONTH, GETDATE(), COALESCE(POL.C_DUEDATE, PO.C_DUEDATE)) < 0
                 THEN 0
                 ELSE DATEDIFF(MONTH, GETDATE(), COALESCE(POL.C_DUEDATE, PO.C_DUEDATE)) END AS MonthOffset,
            ISNULL(POL.C_QUANTITYOUTSTANDING, 0)                              AS Qty
        FROM [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PURCHASEORDER] PO WITH (NOLOCK)
        INNER JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PURCHASEORDER_LINE] POL WITH (NOLOCK)
            ON POL.C__OWNER_ = PO.C_ID
        WHERE PO.C_DATE >= '2026-01-01'
          AND ISNULL(POL.C_QUANTITYOUTSTANDING, 0) > 0
          AND COALESCE(POL.C_DUEDATE, PO.C_DUEDATE) IS NOT NULL
    ) x
    WHERE x.MonthOffset <= 12
    GROUP BY x.ProductID, x.MonthOffset
),
POPiv AS
(
    SELECT ProductID,
        SUM(CASE WHEN MonthOffset = 0 THEN Qty ELSE 0 END) AS PO0,
        SUM(CASE WHEN MonthOffset = 1 THEN Qty ELSE 0 END) AS PO1,
        SUM(CASE WHEN MonthOffset = 2 THEN Qty ELSE 0 END) AS PO2,
        SUM(CASE WHEN MonthOffset = 3 THEN Qty ELSE 0 END) AS PO3,
        SUM(CASE WHEN MonthOffset = 4 THEN Qty ELSE 0 END) AS PO4,
        SUM(CASE WHEN MonthOffset = 5 THEN Qty ELSE 0 END) AS PO5,
        SUM(CASE WHEN MonthOffset = 6 THEN Qty ELSE 0 END) AS PO6,
        SUM(CASE WHEN MonthOffset = 7 THEN Qty ELSE 0 END) AS PO7,
        SUM(CASE WHEN MonthOffset = 8 THEN Qty ELSE 0 END) AS PO8,
        SUM(CASE WHEN MonthOffset = 9 THEN Qty ELSE 0 END) AS PO9,
        SUM(CASE WHEN MonthOffset = 10 THEN Qty ELSE 0 END) AS PO10,
        SUM(CASE WHEN MonthOffset = 11 THEN Qty ELSE 0 END) AS PO11,
        SUM(CASE WHEN MonthOffset = 12 THEN Qty ELSE 0 END) AS PO12
    FROM PoOrdered
    GROUP BY ProductID
),
-- Manual order overrides pivoted by month offset (NULL = nothing entered)
MANPiv AS
(
    SELECT MO.ProductID,
        MAX(CASE WHEN DATEDIFF(MONTH, Cfg.CurrentMonthStart, MO.OrderMonth) = 0 THEN MO.ManualQty END) AS MAN0,
        MAX(CASE WHEN DATEDIFF(MONTH, Cfg.CurrentMonthStart, MO.OrderMonth) = 1 THEN MO.ManualQty END) AS MAN1,
        MAX(CASE WHEN DATEDIFF(MONTH, Cfg.CurrentMonthStart, MO.OrderMonth) = 2 THEN MO.ManualQty END) AS MAN2,
        MAX(CASE WHEN DATEDIFF(MONTH, Cfg.CurrentMonthStart, MO.OrderMonth) = 3 THEN MO.ManualQty END) AS MAN3,
        MAX(CASE WHEN DATEDIFF(MONTH, Cfg.CurrentMonthStart, MO.OrderMonth) = 4 THEN MO.ManualQty END) AS MAN4,
        MAX(CASE WHEN DATEDIFF(MONTH, Cfg.CurrentMonthStart, MO.OrderMonth) = 5 THEN MO.ManualQty END) AS MAN5,
        MAX(CASE WHEN DATEDIFF(MONTH, Cfg.CurrentMonthStart, MO.OrderMonth) = 6 THEN MO.ManualQty END) AS MAN6,
        MAX(CASE WHEN DATEDIFF(MONTH, Cfg.CurrentMonthStart, MO.OrderMonth) = 7 THEN MO.ManualQty END) AS MAN7,
        MAX(CASE WHEN DATEDIFF(MONTH, Cfg.CurrentMonthStart, MO.OrderMonth) = 8 THEN MO.ManualQty END) AS MAN8,
        MAX(CASE WHEN DATEDIFF(MONTH, Cfg.CurrentMonthStart, MO.OrderMonth) = 9 THEN MO.ManualQty END) AS MAN9,
        MAX(CASE WHEN DATEDIFF(MONTH, Cfg.CurrentMonthStart, MO.OrderMonth) = 10 THEN MO.ManualQty END) AS MAN10,
        MAX(CASE WHEN DATEDIFF(MONTH, Cfg.CurrentMonthStart, MO.OrderMonth) = 11 THEN MO.ManualQty END) AS MAN11,
        MAX(CASE WHEN DATEDIFF(MONTH, Cfg.CurrentMonthStart, MO.OrderMonth) = 12 THEN MO.ManualQty END) AS MAN12
    FROM dbo.ForecastOrdering_ManualOrder MO
    CROSS JOIN Cfg
    GROUP BY MO.ProductID
),
-- ---------------------------------------------------------------------------
-- USD supplier details (Excel: "list the USD supplier details, not the GBP").
-- Same selection rule as Dim_Product: highest USD list price per product.
-- ---------------------------------------------------------------------------
USDAlt AS
(
    SELECT
        PI.C__OWNER_                                       AS ProductID,
        S.C_NAME                                           AS SupplierName,
        S.C_CODE                                           AS SupplierCode,
        PPAlt.C_LISTPRICEACTUAL                            AS SupplierCost,
        CUR.C_CODE                                         AS SupplierCurrency,
        ROW_NUMBER() OVER (PARTITION BY PI.C__OWNER_
                           ORDER BY PPAlt.C_LISTPRICEACTUAL DESC) AS rn
    FROM [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCT_ALTERNATEPURCHASINGINFO] PI WITH (NOLOCK)
    INNER JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCT_PURCHASING] PPAlt WITH (NOLOCK)
        ON PPAlt.C_ID = PI.C_ID
    INNER JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_CURRENCY] CUR WITH (NOLOCK)
        ON CUR.C_ID = PPAlt.C_LISTPRICECURRENCY
    LEFT JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_SUPPLIER] S WITH (NOLOCK)
        ON S.C_ID = PPAlt.C_DEFAULTSUPPLIER
    WHERE CUR.C_CODE = 'USD'
),
-- ---------------------------------------------------------------------------
-- Product master for the sheet: AQUAI products that can be ordered
-- (kits, DELIVERY CHARGE and TEXT items excluded)
-- ---------------------------------------------------------------------------
Prod AS
(
    SELECT
        p.C_ID                                                          AS ProductID,
        p.C_CODE                                                        AS TippersCode,
        p.C_DESCRIPTION                                                 AS TippersDescription,
        pp.C_SUPPLIERPRODUCTCODE                                        AS AquaICode,
        pp.C_SUPPLIERPRODUCTDESCRIPTION                                 AS AquaIDescription,
        p.C_D_WyndamCode                                                AS WyndamCode,
        p.C_D_WyndamDescription                                         AS WyndamDescription,
        p.C_ManufacturerProductCode                                     AS SupplierStockCode,
        u.SupplierName,
        CAST(u.SupplierCost AS DECIMAL(18,4))                           AS SupplierCost,
        u.SupplierCurrency,
        CAST(ISNULL(pp.C_D_MOQ, 0) AS DECIMAL(19,4))                    AS MOQ,
        CAST(COALESCE(NULLIF(pp.C_PACKSIZE, 0), 1) AS DECIMAL(19,4))    AS CartonQty,
        CAST(ISNULL((m.C_LENGTH * m.C_WIDTH * m.C_HEIGHT) / 1000000000.0, 0) AS DECIMAL(18,6)) AS CBM,
        CAST(COALESCE(NULLIF(p.C_D_PERCENTAGEGROWTH, 0), 1) AS DECIMAL(18,4)) AS GrowthFactor,
        CASE WHEN p.C_D_COREPRODUCT = 1 THEN 1 ELSE 0 END               AS IsCoreProduct,
        CAST(CASE WHEN p.C_D_COREPRODUCT = 1 THEN Cfg.CoreMonths ELSE Cfg.NonCoreMonths END AS DECIMAL(9,2)) AS RequiredMonthsStock,
        CAST(ISNULL(a.MonthlyAvgSales, 0) AS DECIMAL(19,4))             AS MonthlyAvgSales,
        CAST(ISNULL(pstats.C_STOCKLEVEL, 0) AS DECIMAL(19,4))           AS CurrentStock,
        CAST(ISNULL(a.MonthlyAvgSales, 0)
             * CASE WHEN p.C_D_COREPRODUCT = 1 THEN Cfg.CoreMonths ELSE Cfg.NonCoreMonths END AS DECIMAL(19,4)) AS IdealStockingLevel
    FROM [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCT] p WITH (NOLOCK)
    CROSS JOIN Cfg
    INNER JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCTDEPARTMENT] PD WITH (NOLOCK)
        ON PD.C_ID = p.C_DEPARTMENT
    INNER JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCTDEPARTMENTGROUP] PDG WITH (NOLOCK)
        ON PDG.C_ID = PD.C_GROUP
    LEFT JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCT_STATISTICS] pstats WITH (NOLOCK)
        ON pstats.C_ID = p.C_STATISTICS
    LEFT JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCT_PURCHASING] pp WITH (NOLOCK)
        ON pp.C_ID = p.C_PURCHASING
    LEFT JOIN [Intact_IQ_Walter_Tipper_Ltd].[dbo].[T_PRODUCT_MEASUREMENTS] m WITH (NOLOCK)
        ON m.C_ID = p.C_MEASUREMENTS
    LEFT JOIN USDAlt u
        ON u.ProductID = p.C_ID AND u.rn = 1
    LEFT JOIN AvgSales a
        ON a.ProductID = p.C_ID
    WHERE PDG.C_CODE = 'AQUAI'
      AND p.C_TYPE NOT IN (15, 2, 6, 19, 10, 18)   -- same exclusions as Dim_Product
      AND p.C_TYPE <> 3                            -- kits are not ordered, their components are
      AND p.C_ID <> 21479144630299                 -- system/text item
      -- Exclude DELIVERY CHARGE and TEXT items
      AND UPPER(p.C_CODE) NOT LIKE '%DELIVERY%'
      AND UPPER(ISNULL(p.C_DESCRIPTION, '')) NOT LIKE '%DELIVERY CHARGE%'
      AND UPPER(p.C_CODE) <> 'TEXT'
      AND UPPER(ISNULL(p.C_DESCRIPTION, '')) NOT LIKE 'TEXT%'
),
-- ---------------------------------------------------------------------------
-- Month-by-month chain of Predicted Stock (recursive, 13 steps per product).
-- Month m needs the effective order of month m-1, which needs Predicted Stock of m-1.
-- The recursive step has NO joins: monthly inputs travel with the row as FO/PO/MAN
-- columns and are picked with CHOOSE(), so nothing is re-read from the database.
-- ---------------------------------------------------------------------------
Chain AS
(
    -- Anchor: current month (offset 0), predicted stock = current stock
    SELECT
        p.ProductID,
        p.TippersCode,
        p.TippersDescription,
        p.AquaICode,
        p.AquaIDescription,
        p.WyndamCode,
        p.WyndamDescription,
        p.SupplierStockCode,
        p.SupplierName,
        p.SupplierCost,
        p.SupplierCurrency,
        p.MOQ,
        p.CartonQty,
        p.CBM,
        p.GrowthFactor,
        p.IsCoreProduct,
        p.RequiredMonthsStock,
        p.MonthlyAvgSales,
        p.CurrentStock,
        p.IdealStockingLevel,
        CAST(ISNULL(fo.FO0, 0) AS DECIMAL(19,4)) AS FO0,
        CAST(ISNULL(fo.FO1, 0) AS DECIMAL(19,4)) AS FO1,
        CAST(ISNULL(fo.FO2, 0) AS DECIMAL(19,4)) AS FO2,
        CAST(ISNULL(fo.FO3, 0) AS DECIMAL(19,4)) AS FO3,
        CAST(ISNULL(fo.FO4, 0) AS DECIMAL(19,4)) AS FO4,
        CAST(ISNULL(fo.FO5, 0) AS DECIMAL(19,4)) AS FO5,
        CAST(ISNULL(fo.FO6, 0) AS DECIMAL(19,4)) AS FO6,
        CAST(ISNULL(fo.FO7, 0) AS DECIMAL(19,4)) AS FO7,
        CAST(ISNULL(fo.FO8, 0) AS DECIMAL(19,4)) AS FO8,
        CAST(ISNULL(fo.FO9, 0) AS DECIMAL(19,4)) AS FO9,
        CAST(ISNULL(fo.FO10, 0) AS DECIMAL(19,4)) AS FO10,
        CAST(ISNULL(fo.FO11, 0) AS DECIMAL(19,4)) AS FO11,
        CAST(ISNULL(fo.FO12, 0) AS DECIMAL(19,4)) AS FO12,
        CAST(ISNULL(po.PO0, 0) AS DECIMAL(19,4)) AS PO0,
        CAST(ISNULL(po.PO1, 0) AS DECIMAL(19,4)) AS PO1,
        CAST(ISNULL(po.PO2, 0) AS DECIMAL(19,4)) AS PO2,
        CAST(ISNULL(po.PO3, 0) AS DECIMAL(19,4)) AS PO3,
        CAST(ISNULL(po.PO4, 0) AS DECIMAL(19,4)) AS PO4,
        CAST(ISNULL(po.PO5, 0) AS DECIMAL(19,4)) AS PO5,
        CAST(ISNULL(po.PO6, 0) AS DECIMAL(19,4)) AS PO6,
        CAST(ISNULL(po.PO7, 0) AS DECIMAL(19,4)) AS PO7,
        CAST(ISNULL(po.PO8, 0) AS DECIMAL(19,4)) AS PO8,
        CAST(ISNULL(po.PO9, 0) AS DECIMAL(19,4)) AS PO9,
        CAST(ISNULL(po.PO10, 0) AS DECIMAL(19,4)) AS PO10,
        CAST(ISNULL(po.PO11, 0) AS DECIMAL(19,4)) AS PO11,
        CAST(ISNULL(po.PO12, 0) AS DECIMAL(19,4)) AS PO12,
        CAST(mn.MAN0 AS DECIMAL(19,4)) AS MAN0,
        CAST(mn.MAN1 AS DECIMAL(19,4)) AS MAN1,
        CAST(mn.MAN2 AS DECIMAL(19,4)) AS MAN2,
        CAST(mn.MAN3 AS DECIMAL(19,4)) AS MAN3,
        CAST(mn.MAN4 AS DECIMAL(19,4)) AS MAN4,
        CAST(mn.MAN5 AS DECIMAL(19,4)) AS MAN5,
        CAST(mn.MAN6 AS DECIMAL(19,4)) AS MAN6,
        CAST(mn.MAN7 AS DECIMAL(19,4)) AS MAN7,
        CAST(mn.MAN8 AS DECIMAL(19,4)) AS MAN8,
        CAST(mn.MAN9 AS DECIMAL(19,4)) AS MAN9,
        CAST(mn.MAN10 AS DECIMAL(19,4)) AS MAN10,
        CAST(mn.MAN11 AS DECIMAL(19,4)) AS MAN11,
        CAST(mn.MAN12 AS DECIMAL(19,4)) AS MAN12,
        CAST(0 AS INT)                                                    AS MonthOffset,
        CAST(cfg.CurrentMonthStart AS DATE)                               AS MonthStart,
        CAST(p.CurrentStock AS DECIMAL(19,4))                             AS PredictedStock,
        CAST(ISNULL(fo.FO0, 0) AS DECIMAL(19,4))                          AS ForecastOrdersOutstanding,
        CAST(p.MonthlyAvgSales * p.GrowthFactor + ISNULL(fo.FO0, 0) AS DECIMAL(19,4)) AS ForecastedSales,
        CAST(ISNULL(po.PO0, 0) AS DECIMAL(19,4))                          AS OrderedStock,
        CAST(mn.MAN0 AS DECIMAL(19,4))                                    AS ManualOrderAmount
    FROM Prod p
    CROSS JOIN Cfg cfg
    LEFT JOIN FOPiv  fo ON fo.ProductID = p.ProductID
    LEFT JOIN POPiv  po ON po.ProductID = p.ProductID
    LEFT JOIN MANPiv mn ON mn.ProductID = p.ProductID

    UNION ALL

    -- Step: Predicted(m) = Predicted(m-1) - Forecasted(m-1) + Ordered(m-1) + Effective order(m-1)
    SELECT
        c.ProductID,
        c.TippersCode,
        c.TippersDescription,
        c.AquaICode,
        c.AquaIDescription,
        c.WyndamCode,
        c.WyndamDescription,
        c.SupplierStockCode,
        c.SupplierName,
        c.SupplierCost,
        c.SupplierCurrency,
        c.MOQ,
        c.CartonQty,
        c.CBM,
        c.GrowthFactor,
        c.IsCoreProduct,
        c.RequiredMonthsStock,
        c.MonthlyAvgSales,
        c.CurrentStock,
        c.IdealStockingLevel,
        c.FO0,
        c.FO1,
        c.FO2,
        c.FO3,
        c.FO4,
        c.FO5,
        c.FO6,
        c.FO7,
        c.FO8,
        c.FO9,
        c.FO10,
        c.FO11,
        c.FO12,
        c.PO0,
        c.PO1,
        c.PO2,
        c.PO3,
        c.PO4,
        c.PO5,
        c.PO6,
        c.PO7,
        c.PO8,
        c.PO9,
        c.PO10,
        c.PO11,
        c.PO12,
        c.MAN0,
        c.MAN1,
        c.MAN2,
        c.MAN3,
        c.MAN4,
        c.MAN5,
        c.MAN6,
        c.MAN7,
        c.MAN8,
        c.MAN9,
        c.MAN10,
        c.MAN11,
        c.MAN12,
        c.MonthOffset + 1,
        DATEADD(MONTH, 1, c.MonthStart),
        CAST(c.PredictedStock - c.ForecastedSales + c.OrderedStock
             + COALESCE(c.ManualOrderAmount, CASE WHEN c.IdealStockingLevel - (c.PredictedStock + c.OrderedStock - c.ForecastedSales) <= 0 OR c.IdealStockingLevel - (c.PredictedStock + c.OrderedStock - c.ForecastedSales) < c.MOQ THEN 0 ELSE CEILING((c.IdealStockingLevel - (c.PredictedStock + c.OrderedStock - c.ForecastedSales)) / c.CartonQty) * c.CartonQty END) AS DECIMAL(19,4)),
        CAST(CHOOSE(c.MonthOffset + 2, c.FO0, c.FO1, c.FO2, c.FO3, c.FO4, c.FO5, c.FO6, c.FO7, c.FO8, c.FO9, c.FO10, c.FO11, c.FO12) AS DECIMAL(19,4)),
        CAST(c.MonthlyAvgSales * c.GrowthFactor + CHOOSE(c.MonthOffset + 2, c.FO0, c.FO1, c.FO2, c.FO3, c.FO4, c.FO5, c.FO6, c.FO7, c.FO8, c.FO9, c.FO10, c.FO11, c.FO12) AS DECIMAL(19,4)),
        CAST(CHOOSE(c.MonthOffset + 2, c.PO0, c.PO1, c.PO2, c.PO3, c.PO4, c.PO5, c.PO6, c.PO7, c.PO8, c.PO9, c.PO10, c.PO11, c.PO12) AS DECIMAL(19,4)),
        CAST(CHOOSE(c.MonthOffset + 2, c.MAN0, c.MAN1, c.MAN2, c.MAN3, c.MAN4, c.MAN5, c.MAN6, c.MAN7, c.MAN8, c.MAN9, c.MAN10, c.MAN11, c.MAN12) AS DECIMAL(19,4))
    FROM Chain c
    WHERE c.MonthOffset < 12
)
SELECT
    -- ===== Product Identifying Data =====
    c.ProductID,                                         -- -> Dim_Product[ProductID]
    c.TippersCode,
    c.TippersDescription,
    c.AquaICode,
    c.AquaIDescription,
    c.WyndamCode,
    c.WyndamDescription,
    c.SupplierStockCode,

    -- ===== Useful Product Information =====
    c.SupplierName,                                      -- USD supplier
    c.SupplierCost,
    c.SupplierCurrency,
    c.MOQ,
    c.CartonQty,
    c.CBM,
    c.GrowthFactor,
    c.IsCoreProduct,
    c.RequiredMonthsStock,
    c.IdealStockingLevel,
    CAST(c.CurrentStock       * c.CBM AS DECIMAL(19,4))  AS CurrentSpaceRequirements,
    CAST(c.IdealStockingLevel * c.CBM AS DECIMAL(19,4))  AS IdealStockingLevelSpaceRequirement,
    c.MonthlyAvgSales,

    -- ===== Month columns (current month = MonthOffset 0, then rolling 12 months) =====
    c.MonthOffset,
    c.MonthStart,
    CONVERT(CHAR(7), c.MonthStart, 126)                  AS MonthLabel,           -- 'YYYY-MM'
    c.PredictedStock                                     AS StockHolding,         -- Current Stock (month 0) / Predicted Stock (later)
    c.ForecastOrdersOutstanding,
    CAST((c.PredictedStock - c.ForecastOrdersOutstanding) / NULLIF(c.MonthlyAvgSales, 0) AS DECIMAL(19,2)) AS MonthsStockRemaining,
    c.OrderedStock,
    c.ForecastedSales,
    s.SuggestedOrderAmount,
    c.ManualOrderAmount,
    COALESCE(c.ManualOrderAmount, s.SuggestedOrderAmount) AS EffectiveOrderAmount,
    CAST(COALESCE(c.ManualOrderAmount, s.SuggestedOrderAmount) * c.SupplierCost AS DECIMAL(19,2)) AS ContainerValue,
    CAST(COALESCE(c.ManualOrderAmount, s.SuggestedOrderAmount) * c.CBM          AS DECIMAL(19,4)) AS SpaceRequiredForOrder
FROM Chain c
CROSS APPLY (
    -- Suggested Order Amount: Ideal - (Stock + Ordered - Forecasted); < MOQ -> 0; round UP to full cartons
    SELECT CAST(CASE WHEN c.IdealStockingLevel - (c.PredictedStock + c.OrderedStock - c.ForecastedSales) <= 0 OR c.IdealStockingLevel - (c.PredictedStock + c.OrderedStock - c.ForecastedSales) < c.MOQ THEN 0 ELSE CEILING((c.IdealStockingLevel - (c.PredictedStock + c.OrderedStock - c.ForecastedSales)) / c.CartonQty) * c.CartonQty END AS DECIMAL(19,4)) AS SuggestedOrderAmount
) s;
GO