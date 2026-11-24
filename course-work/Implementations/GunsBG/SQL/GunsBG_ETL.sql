/*
    Guns.bg Coursework | ETL: GunsBG -> GunsBG_DWH (SQL Server)

    Prerequisites (run in this order):
        1) GunsBG_full_setup.sql
        2) GunsBG_DWH.sql
        3) THIS FILE

    ETL method:
      * Extract from GunsBG.dbo OLTP tables
      * Transform to 7 dimensions + 3 fact tables
      * Load/update existing rows by stable OLTP business keys
      * Daily inventory snapshots: rerunning on the same day REPLACES
        that day's counts, but older snapshot days remain intact.

    Revenue policy for FactSales:
      Order status IN ('Processing', 'Completed'), total successful
      payments >= order total, and no refund event recorded.
      This is a coursework definition of booked paid sales, not a
      statement about Guns.bg accounting policies.

    FactOrders represents latest/current order state (Type 1): last
    payment attempt and shipment. Dimension changes also overwrite
    previous descriptions (Type 1). Reruns are idempotent.
*/

IF DB_ID(N'GunsBG') IS NULL
    THROW 51000, N'Missing OLTP database GunsBG. Run GunsBG_full_setup.sql first.', 1;
GO
IF DB_ID(N'GunsBG_DWH') IS NULL
    THROW 51001, N'Missing warehouse database GunsBG_DWH. Run GunsBG_DWH.sql first.', 1;
GO
USE GunsBG_DWH;
GO

CREATE OR ALTER PROCEDURE dbo.usp_LoadGunsBG_DWH
    @SnapshotDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @AsOfDate DATE = COALESCE(@SnapshotDate, CONVERT(DATE, SYSDATETIME()));
    DECLARE @InventoryDateKey INT = CONVERT(INT, CONVERT(CHAR(8), @AsOfDate, 112));

    IF OBJECT_ID(N'GunsBG.dbo.Orders', N'U') IS NULL
       OR OBJECT_ID(N'GunsBG.dbo.OrderItems', N'U') IS NULL
       OR OBJECT_ID(N'GunsBG.dbo.Products', N'U') IS NULL
       OR OBJECT_ID(N'GunsBG.dbo.Inventory', N'U') IS NULL
       OR OBJECT_ID(N'GunsBG.dbo.Payments', N'U') IS NULL
       OR OBJECT_ID(N'GunsBG.dbo.Shipments', N'U') IS NULL
       OR OBJECT_ID(N'GunsBG.dbo.Customers', N'U') IS NULL
       OR OBJECT_ID(N'GunsBG.dbo.Categories', N'U') IS NULL
       OR OBJECT_ID(N'GunsBG.dbo.Brands', N'U') IS NULL
        THROW 51002, N'OLTP tables are missing. Run GunsBG_full_setup.sql.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        /* 1. DIMDATE: all order dates + the requested snapshot day. */
        ;WITH DatesToLoad AS (
            SELECT CONVERT(DATE, o.OrderDate) AS FullDate
            FROM GunsBG.dbo.Orders AS o
            UNION
            SELECT @AsOfDate
        )
        INSERT INTO dbo.DimDate
            (DateKey, FullDate, DayNumber, MonthNumber, QuarterNumber, YearNumber)
        SELECT CONVERT(INT, CONVERT(CHAR(8), d.FullDate, 112)),
               d.FullDate,
               DATEPART(DAY, d.FullDate),
               DATEPART(MONTH, d.FullDate),
               DATEPART(QUARTER, d.FullDate),
               DATEPART(YEAR, d.FullDate)
        FROM DatesToLoad AS d
        WHERE NOT EXISTS (
            SELECT 1 FROM dbo.DimDate AS target WHERE target.FullDate = d.FullDate
        );

        /* 2. DIMCATEGORY / DIMBRAND: upsert Type 1 descriptions. */
        UPDATE target
           SET CategoryName = src.Name
        FROM dbo.DimCategory AS target
        JOIN GunsBG.dbo.Categories AS src ON src.CategoryID = target.CategoryID;

        INSERT INTO dbo.DimCategory (CategoryID, CategoryName)
        SELECT src.CategoryID, src.Name
        FROM GunsBG.dbo.Categories AS src
        WHERE NOT EXISTS (
            SELECT 1 FROM dbo.DimCategory AS target WHERE target.CategoryID = src.CategoryID
        );

        UPDATE target
           SET BrandName = src.Name
        FROM dbo.DimBrand AS target
        JOIN GunsBG.dbo.Brands AS src ON src.BrandID = target.BrandID;

        INSERT INTO dbo.DimBrand (BrandID, BrandName)
        SELECT src.BrandID, src.Name
        FROM GunsBG.dbo.Brands AS src
        WHERE NOT EXISTS (
            SELECT 1 FROM dbo.DimBrand AS target WHERE target.BrandID = src.BrandID
        );

        /* 3. DIMCUSTOMER: upsert Type 1 descriptions. */
        UPDATE target
           SET CustomerName = src.Name,
               Email = src.Email
        FROM dbo.DimCustomer AS target
        JOIN GunsBG.dbo.Customers AS src ON src.CustomerID = target.CustomerID;

        INSERT INTO dbo.DimCustomer (CustomerID, CustomerName, Email)
        SELECT src.CustomerID, src.Name, src.Email
        FROM GunsBG.dbo.Customers AS src
        WHERE NOT EXISTS (
            SELECT 1 FROM dbo.DimCustomer AS target WHERE target.CustomerID = src.CustomerID
        );

        /* 4. DIMPRODUCT: lookup dimension surrogate keys from source category/brand. */
        UPDATE target
           SET CategoryKey = cat.CategoryKey,
               BrandKey = brand.BrandKey,
               ProductName = src.Name,
               SKU = src.SKU,
               Regulated = src.Regulated
        FROM dbo.DimProduct AS target
        JOIN GunsBG.dbo.Products AS src ON src.ProductID = target.ProductID
        JOIN dbo.DimCategory AS cat ON cat.CategoryID = src.CategoryID
        JOIN dbo.DimBrand AS brand ON brand.BrandID = src.BrandID;

        INSERT INTO dbo.DimProduct
            (ProductID, CategoryKey, BrandKey, ProductName, SKU, Regulated)
        SELECT src.ProductID, cat.CategoryKey, brand.BrandKey,
               src.Name, src.SKU, src.Regulated
        FROM GunsBG.dbo.Products AS src
        JOIN dbo.DimCategory AS cat ON cat.CategoryID = src.CategoryID
        JOIN dbo.DimBrand AS brand ON brand.BrandID = src.BrandID
        WHERE NOT EXISTS (
            SELECT 1 FROM dbo.DimProduct AS target WHERE target.ProductID = src.ProductID
        );

        /* 5. DIMPAYMENT / DIMSHIPMENT: one record per status+method,
              including explicit states for missing payment/shipment. */
        ;WITH PaymentPairs AS (
            SELECT p.Method, p.Status FROM GunsBG.dbo.Payments AS p
            UNION
            SELECT CAST(N'None' AS NVARCHAR(50)), CAST(N'NoPayment' AS NVARCHAR(30))
        )
        INSERT INTO dbo.DimPayment (Method, Status)
        SELECT src.Method, src.Status
        FROM PaymentPairs AS src
        WHERE NOT EXISTS (
            SELECT 1 FROM dbo.DimPayment AS target
            WHERE target.Method = src.Method AND target.Status = src.Status
        );

        ;WITH ShipmentPairs AS (
            SELECT s.ShippingMethod, s.Status FROM GunsBG.dbo.Shipments AS s
            UNION
            SELECT CAST(N'None' AS NVARCHAR(50)), CAST(N'NotShipped' AS NVARCHAR(30))
        )
        INSERT INTO dbo.DimShipment (ShippingMethod, Status)
        SELECT src.ShippingMethod, src.Status
        FROM ShipmentPairs AS src
        WHERE NOT EXISTS (
            SELECT 1 FROM dbo.DimShipment AS target
            WHERE target.ShippingMethod = src.ShippingMethod AND target.Status = src.Status
        );

        /* 6. FACTORDERS: 1 record per OLTP order, including pending orders.
              Payment = latest attempt (timestamp, then PaymentID as tiebreaker).
              Shipment = current linked shipment, or 'NotShipped'. */
        SELECT o.OrderID,
               d.DateKey,
               dc.CustomerKey,
               dp.PaymentKey,
               ds.ShipmentKey,
               o.Status AS OrderStatus,
               o.TotalPrice AS OrderTotal,
               itemSummary.LineItemCount,
               itemSummary.TotalQuantity
        INTO #SourceOrders
        FROM GunsBG.dbo.Orders AS o
        JOIN dbo.DimDate AS d ON d.FullDate = CONVERT(DATE, o.OrderDate)
        JOIN dbo.DimCustomer AS dc ON dc.CustomerID = o.CustomerID
        OUTER APPLY (
            SELECT TOP (1) p.Method, p.Status
            FROM GunsBG.dbo.Payments AS p
            WHERE p.OrderID = o.OrderID
            ORDER BY p.PaymentDate DESC, p.PaymentID DESC
        ) AS latestPayment
        OUTER APPLY (
            SELECT TOP (1) s.ShippingMethod, s.Status
            FROM GunsBG.dbo.Shipments AS s
            WHERE s.OrderID = o.OrderID
            ORDER BY s.ShipmentID DESC
        ) AS latestShipment
        OUTER APPLY (
            SELECT CONVERT(INT, COUNT(*)) AS LineItemCount,
                   CONVERT(INT, COALESCE(SUM(oi.Quantity), 0)) AS TotalQuantity
            FROM GunsBG.dbo.OrderItems AS oi
            WHERE oi.OrderID = o.OrderID
        ) AS itemSummary
        JOIN dbo.DimPayment AS dp
          ON dp.Method = COALESCE(latestPayment.Method, N'None')
         AND dp.Status = COALESCE(latestPayment.Status, N'NoPayment')
        JOIN dbo.DimShipment AS ds
          ON ds.ShippingMethod = COALESCE(latestShipment.ShippingMethod, N'None')
         AND ds.Status = COALESCE(latestShipment.Status, N'NotShipped');

        UPDATE f
           SET DateKey = s.DateKey,
               CustomerKey = s.CustomerKey,
               PaymentKey = s.PaymentKey,
               ShipmentKey = s.ShipmentKey,
               OrderStatus = s.OrderStatus,
               OrderTotal = s.OrderTotal,
               LineItemCount = s.LineItemCount,
               TotalQuantity = s.TotalQuantity
        FROM dbo.FactOrders AS f
        JOIN #SourceOrders AS s ON s.OrderID = f.OrderID;

        INSERT INTO dbo.FactOrders
            (DateKey, CustomerKey, PaymentKey, ShipmentKey, OrderID,
             OrderStatus, OrderTotal, LineItemCount, TotalQuantity)
        SELECT s.DateKey, s.CustomerKey, s.PaymentKey, s.ShipmentKey,
               s.OrderID, s.OrderStatus, s.OrderTotal,
               s.LineItemCount, s.TotalQuantity
        FROM #SourceOrders AS s
        WHERE NOT EXISTS (
            SELECT 1 FROM dbo.FactOrders AS f WHERE f.OrderID = s.OrderID
        );

        DELETE f FROM dbo.FactOrders AS f
        WHERE NOT EXISTS (SELECT 1 FROM #SourceOrders AS s WHERE s.OrderID = f.OrderID);

        /* 7. FACTSALES: paid, processed order lines, excluding refunded orders.
              One line per OrderItemID, using historic UnitPrice + discount. */
        SELECT oi.OrderItemID,
               oi.OrderID,
               d.DateKey,
               dc.CustomerKey,
               prod.ProductKey,
               oi.Quantity,
               oi.UnitPrice,
               oi.DiscountPercentage,
               CAST(ROUND(oi.Quantity * oi.UnitPrice *
                     (1 - oi.DiscountPercentage / 100.0), 2)
                     AS DECIMAL(12,2)) AS SalesAmount
        INTO #SourceSales
        FROM GunsBG.dbo.OrderItems AS oi
        JOIN GunsBG.dbo.Orders AS o ON o.OrderID = oi.OrderID
        JOIN dbo.DimDate AS d ON d.FullDate = CONVERT(DATE, o.OrderDate)
        JOIN dbo.DimCustomer AS dc ON dc.CustomerID = o.CustomerID
        JOIN dbo.DimProduct AS prod ON prod.ProductID = oi.ProductID
        WHERE o.Status IN (N'Processing', N'Completed')
          AND COALESCE((
                SELECT SUM(p.Amount)
                FROM GunsBG.dbo.Payments AS p
                WHERE p.OrderID = o.OrderID AND p.Status = N'Succeeded'
          ), 0) >= o.TotalPrice
          AND NOT EXISTS (
                SELECT 1 FROM GunsBG.dbo.Payments AS refund
                WHERE refund.OrderID = o.OrderID AND refund.Status = N'Refunded'
          );

        UPDATE f
           SET OrderID = s.OrderID,
               DateKey = s.DateKey,
               CustomerKey = s.CustomerKey,
               ProductKey = s.ProductKey,
               Quantity = s.Quantity,
               UnitPrice = s.UnitPrice,
               DiscountPercentage = s.DiscountPercentage,
               SalesAmount = s.SalesAmount
        FROM dbo.FactSales AS f
        JOIN #SourceSales AS s ON s.OrderItemID = f.OrderItemID;

        INSERT INTO dbo.FactSales
            (DateKey, CustomerKey, ProductKey, OrderItemID, OrderID,
             Quantity, UnitPrice, DiscountPercentage, SalesAmount)
        SELECT s.DateKey, s.CustomerKey, s.ProductKey, s.OrderItemID, s.OrderID,
               s.Quantity, s.UnitPrice, s.DiscountPercentage, s.SalesAmount
        FROM #SourceSales AS s
        WHERE NOT EXISTS (
            SELECT 1 FROM dbo.FactSales AS f WHERE f.OrderItemID = s.OrderItemID
        );

        DELETE f FROM dbo.FactSales AS f
        WHERE NOT EXISTS (SELECT 1 FROM #SourceSales AS s WHERE s.OrderItemID = f.OrderItemID);

        /* 8. FACTINVENTORY: snapshot of current stock at @AsOfDate.
              Running ETL twice for same day updates, not duplicates. */
        SELECT @InventoryDateKey AS DateKey,
               product.ProductKey,
               inv.AvailableQuantity
        INTO #SourceInventory
        FROM GunsBG.dbo.Inventory AS inv
        JOIN dbo.DimProduct AS product ON product.ProductID = inv.ProductID;

        UPDATE f
           SET AvailableQuantity = s.AvailableQuantity
        FROM dbo.FactInventory AS f
        JOIN #SourceInventory AS s
          ON s.DateKey = f.DateKey AND s.ProductKey = f.ProductKey;

        INSERT INTO dbo.FactInventory (DateKey, ProductKey, AvailableQuantity)
        SELECT s.DateKey, s.ProductKey, s.AvailableQuantity
        FROM #SourceInventory AS s
        WHERE NOT EXISTS (
            SELECT 1 FROM dbo.FactInventory AS f
            WHERE f.DateKey = s.DateKey AND f.ProductKey = s.ProductKey
        );

        DELETE f FROM dbo.FactInventory AS f
        WHERE f.DateKey = @InventoryDateKey
          AND NOT EXISTS (
                SELECT 1 FROM #SourceInventory AS s
                WHERE s.DateKey = f.DateKey AND s.ProductKey = f.ProductKey
          );

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

-- Load current source OLTP data and today's inventory snapshot.
EXEC dbo.usp_LoadGunsBG_DWH;
GO

-- Verification after loading
SELECT N'DimDate' AS TableName, COUNT(*) AS RowCount FROM dbo.DimDate
UNION ALL SELECT N'DimCustomer', COUNT(*) FROM dbo.DimCustomer
UNION ALL SELECT N'DimProduct', COUNT(*) FROM dbo.DimProduct
UNION ALL SELECT N'DimCategory', COUNT(*) FROM dbo.DimCategory
UNION ALL SELECT N'DimBrand', COUNT(*) FROM dbo.DimBrand
UNION ALL SELECT N'DimPayment', COUNT(*) FROM dbo.DimPayment
UNION ALL SELECT N'DimShipment', COUNT(*) FROM dbo.DimShipment
UNION ALL SELECT N'FactSales', COUNT(*) FROM dbo.FactSales
UNION ALL SELECT N'FactOrders', COUNT(*) FROM dbo.FactOrders
UNION ALL SELECT N'FactInventory', COUNT(*) FROM dbo.FactInventory;
GO

SELECT SUM(SalesAmount) AS PaidSalesAmount,
       SUM(Quantity) AS SoldUnits
FROM dbo.FactSales;
GO

SELECT o.OrderID, o.OrderStatus, o.OrderTotal,
       p.Method AS PaymentMethod, p.Status AS PaymentStatus,
       s.ShippingMethod, s.Status AS ShipmentStatus
FROM dbo.FactOrders AS o
JOIN dbo.DimPayment AS p ON p.PaymentKey = o.PaymentKey
JOIN dbo.DimShipment AS s ON s.ShipmentKey = o.ShipmentKey
ORDER BY o.OrderID;
GO
