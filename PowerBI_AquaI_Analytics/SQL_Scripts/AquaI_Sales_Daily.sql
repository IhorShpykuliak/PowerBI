--CREATE OR ALTER VIEW dbo.vw_AquaI_Sales_Daily AS
USE [Tippers];
GO

IF OBJECT_ID('dbo.Fact_AquaI_Sales_Daily', 'V') IS NOT NULL
    DROP VIEW dbo.Fact_AquaI_Sales_Daily;
GO

CREATE VIEW dbo.Fact_AquaI_Sales_Daily AS
WITH SA AS (
    -- Fact_SalesAnalysis (AquaI only), one row per customer per day
    SELECT
        UPPER(LTRIM(RTRIM(sa.CustomerCode)))                      AS CustomerCodeNorm,
        sa.SalesDateKey  AS SalesDate,
        SUM(ISNULL(sa.NetSalesAmount, 0))                         AS Sales,
        SUM(ISNULL(sa.NetCostAmount, 0))                          AS Cost
    FROM Tippers.dbo.Fact_SalesAnalysis sa
    WHERE sa.CustomerCode IS NOT NULL
      AND (sa.CostCentre = 'AI' OR sa.BranchID IN (4337992263054, 4337992263053))
      AND sa.CustomerCode NOT LIKE 'INTERCO%'
      AND sa.CustomerCode <> 'WALT0001'
    GROUP BY UPPER(LTRIM(RTRIM(sa.CustomerCode))),
             sa.SalesDateKey
),
CDM AS (
    -- historical snapshot, one row per customer per day
    SELECT
        UPPER(LTRIM(RTRIM(customer_code))) AS CustomerCodeNorm,
        sales_date                         AS SalesDate,
        SUM(ISNULL(daily_sales, 0))        AS Sales,
        SUM(ISNULL(daily_cost, 0))         AS Cost,
        SUM(ISNULL(gp_value, 0))           AS GP
    FROM Tippers.dbo.CustomerDailyMetricsAquaI
    WHERE customer_code <> 'WALT0001'
    GROUP BY UPPER(LTRIM(RTRIM(customer_code))), sales_date
)
SELECT
    COALESCE(sa.CustomerCodeNorm, c.CustomerCodeNorm)                    AS CustomerCodeNorm,
    COALESCE(sa.SalesDate, c.SalesDate)                                  AS SalesDate,
    CAST(FORMAT(COALESCE(sa.SalesDate, c.SalesDate), 'yyyyMMdd') AS INT) AS DateKey,
    CASE WHEN sa.CustomerCodeNorm IS NOT NULL THEN sa.Sales ELSE c.Sales END AS Sales,
    CASE WHEN sa.CustomerCodeNorm IS NOT NULL THEN sa.Cost  ELSE c.Cost  END AS Cost,
    CASE WHEN sa.CustomerCodeNorm IS NOT NULL THEN sa.Sales - sa.Cost ELSE c.GP END AS GP
  
FROM SA sa
FULL OUTER JOIN CDM c
       ON c.CustomerCodeNorm = sa.CustomerCodeNorm
      AND c.SalesDate = sa.SalesDate
WHERE COALESCE(sa.SalesDate, c.SalesDate) >= DATEFROMPARTS(YEAR(GETDATE()) - 1, 1, 1);