/*******************************************************************************
  Script Name:  Create_Dim_Date.sql
  Description:  Creates and populates an enterprise-grade Date Dimension (Dim_Date)
                for Power BI models, SQL views, and Data Warehouse architectures.
  Date Range:   2020-01-01 to 2030-12-31
  Author:       Ihor Shpykuliak
*******************************************************************************/

USE [Tippers];
GO

-- 1. Drop existing Dim_Date table if it exists
IF OBJECT_ID('dbo.Dim_Date', 'U') IS NOT NULL
    DROP TABLE dbo.Dim_Date;
GO

-- 2. Create Dim_Date Table Structure
CREATE TABLE dbo.Dim_Date (
    DateKey             INT NOT NULL PRIMARY KEY,   -- Primary Key (Format: YYYYMMDD, e.g., 20260923)
    [Date]              DATE NOT NULL,              -- Standard Date (Used for 1:* relationship with Fact tables)
    [Year]              INT NOT NULL,               -- Year number (e.g., 2026)
    Quarter             TINYINT NOT NULL,           -- Quarter number (1-4)
    QuarterName         CHAR(2) NOT NULL,           -- Quarter label (Q1, Q2, Q3, Q4)
    MonthNumber         TINYINT NOT NULL,           -- Month number (1-12)
    MonthName           VARCHAR(15) NOT NULL,       -- Full Month name (e.g., September)
    MonthNameShort      CHAR(3) NOT NULL,           -- Short Month name (e.g., Sep)
    YearMonth           INT NOT NULL,               -- Sorting Key for Year-Month (e.g., 202609)
    YearMonthName       CHAR(7) NOT NULL,           -- Display label for Year-Month (e.g., 2026-09)
    WeekOfYear          TINYINT NOT NULL,           -- ISO Week number of the year (1-53)
    DayOfMonth          TINYINT NOT NULL,           -- Day of the month (1-31)
    DayOfWeekNumber     TINYINT NOT NULL,           -- Day of the week number (1 = Monday, 7 = Sunday)
    DayOfWeekName       VARCHAR(15) NOT NULL,       -- Full Day name (e.g., Wednesday)
    DayOfWeekNameShort  CHAR(3) NOT NULL,           -- Short Day name (e.g., Wed)
    IsWeekend           BIT NOT NULL,               -- 1 for Saturday/Sunday, 0 for Weekdays
    IsLeapYear          BIT NOT NULL                -- 1 for Leap Year, 0 otherwise
);
GO

-- 3. Populate Dim_Date using Recursive CTE
SET DATEFIRST 1; -- Set Monday as the first day of the week (ISO standard)

DECLARE @StartDate DATE = '2020-01-01';
DECLARE @EndDate   DATE = '2030-12-31';

WITH DateSequence AS (
    SELECT @StartDate AS [Date]
    UNION ALL
    SELECT DATEADD(DAY, 1, [Date])
    FROM DateSequence
    WHERE [Date] < @EndDate
)
INSERT INTO dbo.Dim_Date
SELECT 
    CAST(CONVERT(VARCHAR(8), [Date], 112) AS INT)                                   AS DateKey,
    [Date],
    YEAR([Date])                                                                   AS [Year],
    DATEPART(QUARTER, [Date])                                                      AS Quarter,
    'Q' + CAST(DATEPART(QUARTER, [Date]) AS CHAR(1))                               AS QuarterName,
    MONTH([Date])                                                                  AS MonthNumber,
    DATENAME(MONTH, [Date])                                                        AS MonthName,
    LEFT(DATENAME(MONTH, [Date]), 3)                                              AS MonthNameShort,
    YEAR([Date]) * 100 + MONTH([Date])                                             AS YearMonth,
    CAST(YEAR([Date]) AS CHAR(4)) + '-' + RIGHT('0' + CAST(MONTH([Date]) AS VARCHAR(2)), 2) AS YearMonthName,
    DATEPART(WEEK, [Date])                                                         AS WeekOfYear,
    DAY([Date])                                                                    AS DayOfMonth,
    DATEPART(WEEKDAY, [Date])                                                      AS DayOfWeekNumber,
    DATENAME(WEEKDAY, [Date])                                                      AS DayOfWeekName,
    LEFT(DATENAME(WEEKDAY, [Date]), 3)                                             AS DayOfWeekNameShort,
    CASE WHEN DATEPART(WEEKDAY, [Date]) IN (6, 7) THEN 1 ELSE 0 END               AS IsWeekend,
    CASE WHEN (YEAR([Date]) % 4 = 0 AND YEAR([Date]) % 100 <> 0) OR (YEAR([Date]) % 400 = 0) 
         THEN 1 ELSE 0 END                                                         AS IsLeapYear
FROM DateSequence
OPTION (MAXRECURSION 0);
GO

-- 4. Create Non-Clustered Indexes for Query Optimization
CREATE NONCLUSTERED INDEX IX_Dim_Date_Date ON dbo.Dim_Date([Date]);
CREATE NONCLUSTERED INDEX IX_Dim_Date_YearMonth ON dbo.Dim_Date(YearMonth);
GO