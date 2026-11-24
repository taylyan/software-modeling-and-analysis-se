/*
  Guns.bg coursework | Seed data for Power BI (Microsoft SQL Server)
  ==================================================================
  Requires: GunsBG_full_setup.sql and the existing OLTP 13-table schema.
  Optional: GunsBG_DWH.sql + GunsBG_ETL_fixed.sql already installed.

  Adds exactly 150 distinct coursework orders, dated 15 Jan - 09 Nov 2026,
  plus 30 fictitious customers, 20 fictitious products, promotion links,
  payments, shipments and simulated compliance checks where needed.

  RERUN-SAFE: deterministic customer emails, product SKUs and unique
  CustomerID+OrderDate pairs identify this batch. No existing orders,
  products, or inventory rows are deleted, and processed orders are not
  processed again. Only newly pending coursework orders are processed.

  All names, contacts, permissions and transactions are FICTIONAL.
  This script does NOT model actual Guns.bg customers or sales.
*/

IF DB_ID(N'GunsBG') IS NULL
    THROW 52000, N'GunsBG does not exist. Run GunsBG_full_setup.sql first.', 1;
GO
USE GunsBG;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF OBJECT_ID(N'dbo.usp_ProcessOrder', N'P') IS NULL
    THROW 52001, N'Missing dbo.usp_ProcessOrder. Run GunsBG_full_setup.sql first.', 1;
IF OBJECT_ID(N'dbo.trg_OrderItems_RecalculateTotal', N'TR') IS NULL
    THROW 52002, N'Missing OrderItems trigger. Run GunsBG_full_setup.sql first.', 1;

-- Remove leftover temporary tables when the script is run again in the same SSMS session.
DROP TABLE IF EXISTS #SeedOrderMap;
DROP TABLE IF EXISTS #SeedOrders;
DROP TABLE IF EXISTS #SeedProducts;
DROP TABLE IF EXISTS #SeedCustomers;

BEGIN TRY
    BEGIN TRANSACTION;

    /* 1) Reference categories and demo brands. */
    ;WITH categories AS (
        SELECT v.Name FROM (VALUES
          (N'Ловна екипировка'), (N'Оптика'), (N'Боеприпаси'),
          (N'Аксесоари'), (N'Поддръжка'), (N'Обувки'),
          (N'Туристическо оборудване')
        ) AS v(Name)
    )
    INSERT dbo.Categories (Name)
    SELECT c.Name FROM categories AS c
    WHERE NOT EXISTS (SELECT 1 FROM dbo.Categories AS x WHERE x.Name = c.Name);

    ;WITH brands AS (
        SELECT v.Name FROM (VALUES
          (N'Demo Outdoor'), (N'Demo Optics'),
          (N'Учебна марка Atlas'), (N'Учебна марка Boreal'),
          (N'Учебна марка Cedar')
        ) AS v(Name)
    )
    INSERT dbo.Brands (Name)
    SELECT b.Name FROM brands AS b
    WHERE NOT EXISTS (SELECT 1 FROM dbo.Brands AS x WHERE x.Name = b.Name);

    /* 2) Stable fictitious customer records + one shipping address each. */
    CREATE TABLE #SeedCustomers (
        ClientNo INT NOT NULL PRIMARY KEY,
        CustomerName NVARCHAR(100) NOT NULL,
        Email NVARCHAR(150) NOT NULL,
        Phone NVARCHAR(20) NOT NULL,
        City NVARCHAR(100) NOT NULL,
        Street NVARCHAR(200) NOT NULL,
        PostCode NVARCHAR(10) NOT NULL
    );

    ;WITH seq AS (
        SELECT TOP (30) CONVERT(INT, ROW_NUMBER() OVER (ORDER BY (SELECT NULL))) AS n
        FROM sys.all_objects
    )
    INSERT INTO #SeedCustomers
        (ClientNo, CustomerName, Email, Phone, City, Street, PostCode)
    SELECT n,
           N'Учебен клиент ' + RIGHT(N'00' + CONVERT(NVARCHAR(10), n), 2),
           N'gunsbg.seed26.' + RIGHT(N'00' + CONVERT(NVARCHAR(10), n), 2) + N'@example.test',
           N'0888' + RIGHT(N'000000' + CONVERT(NVARCHAR(10), 200000 + n), 6),
           CASE n % 5 WHEN 0 THEN N'Пловдив' WHEN 1 THEN N'София'
                      WHEN 2 THEN N'Варна' WHEN 3 THEN N'Бургас' ELSE N'Русе' END,
           N'ул. Учебна ' + CONVERT(NVARCHAR(10), n),
           CASE n % 5 WHEN 0 THEN N'4000' WHEN 1 THEN N'1000'
                      WHEN 2 THEN N'9000' WHEN 3 THEN N'8000' ELSE N'7000' END
    FROM seq;

    INSERT INTO dbo.Customers (Name, Email, Phone)
    SELECT x.CustomerName, x.Email, x.Phone
    FROM #SeedCustomers AS x
    WHERE NOT EXISTS (SELECT 1 FROM dbo.Customers AS c WHERE c.Email = x.Email);

    INSERT INTO dbo.Addresses (CustomerID, City, Street, PostCode)
    SELECT c.CustomerID, x.City, x.Street, x.PostCode
    FROM #SeedCustomers AS x
    JOIN dbo.Customers AS c ON c.Email = x.Email
    WHERE NOT EXISTS (
        SELECT 1 FROM dbo.Addresses AS a
        WHERE a.CustomerID = c.CustomerID AND a.Street = x.Street AND a.City = x.City
    );

    /* 3) Twenty fictitious products. All prices are synthetic in EUR. */
    CREATE TABLE #SeedProducts (
        ProductNo INT NOT NULL PRIMARY KEY,
        SKU NVARCHAR(50) NOT NULL,
        ProductName NVARCHAR(150) NOT NULL,
        CategoryName NVARCHAR(100) NOT NULL,
        BrandName NVARCHAR(100) NOT NULL,
        Price DECIMAL(12,2) NOT NULL,
        Regulated BIT NOT NULL
    );

    INSERT INTO #SeedProducts
       (ProductNo, SKU, ProductName, CategoryName, BrandName, Price, Regulated)
    VALUES
       ( 1,N'EDU26-JACKET',      N'Ловно яке (учебно)',                  N'Ловна екипировка',       N'Demo Outdoor',        159.90,0),
       ( 2,N'EDU26-BACKPACK',    N'Раница (учебна)',                    N'Ловна екипировка',       N'Учебна марка Atlas',  74.90,0),
       ( 3,N'EDU26-GLOVES',      N'Ръкавици (учебни)',                  N'Ловна екипировка',       N'Учебна марка Boreal', 22.50,0),
       ( 4,N'EDU26-SHIRT',       N'Термо блуза (учебна)',               N'Ловна екипировка',       N'Demo Outdoor',         38.00,0),
       ( 5,N'EDU26-BINOCULARS',  N'Бинокъл (учебен)',                   N'Оптика',                 N'Demo Optics',         299.90,0),
       ( 6,N'EDU26-RANGEFINDER', N'Далекомер (учебен)',                 N'Оптика',                 N'Demo Optics',         499.00,0),
       ( 7,N'EDU26-OPTICCASE',   N'Калъф за оптика (учебен)',           N'Оптика',                 N'Учебна марка Cedar',  22.50,0),
       ( 8,N'EDU26-CLEANKIT',    N'Комплект за почистване (учебен)',   N'Поддръжка',              N'Учебна марка Atlas',  38.90,0),
       ( 9,N'EDU26-CLEANCLOTH',  N'Кърпа за поддръжка (учебна)',        N'Поддръжка',              N'Учебна марка Cedar',  14.50,0),
       (10,N'EDU26-BOOTS',       N'Туристически обувки (учебни)',       N'Обувки',                 N'Учебна марка Boreal',129.90,0),
       (11,N'EDU26-SOCKS',       N'Чорапи (учебни)',                    N'Обувки',                 N'Demo Outdoor',         12.90,0),
       (12,N'EDU26-FLASHLIGHT',  N'Фенер (учебен)',                     N'Аксесоари',              N'Учебна марка Atlas',  45.90,0),
       (13,N'EDU26-HEADLAMP',    N'Челник (учебен)',                    N'Аксесоари',              N'Учебна марка Boreal', 33.90,0),
       (14,N'EDU26-BOTTLE',      N'Термос (учебен)',                    N'Аксесоари',              N'Учебна марка Cedar',  24.90,0),
       (15,N'EDU26-TENT',        N'Палатка (учебна)',                   N'Туристическо оборудване',N'Учебна марка Atlas', 179.00,0),
       (16,N'EDU26-SLEEPBAG',    N'Спален чувал (учебен)',              N'Туристическо оборудване',N'Учебна марка Boreal', 89.00,0),
       (17,N'EDU26-CHAIR',       N'Сгъваем стол (учебен)',              N'Туристическо оборудване',N'Demo Outdoor',         45.00,0),
       (18,N'EDU26-EARPROTECT',  N'Антифони (учебни)',                  N'Аксесоари',              N'Учебна марка Cedar',  34.90,0),
       (19,N'EDU26-AMMO-A',      N'Боеприпаси A (само учебен запис)',  N'Боеприпаси',             N'Учебна марка Atlas',  29.90,1),
       (20,N'EDU26-AMMO-B',      N'Боеприпаси B (само учебен запис)',  N'Боеприпаси',             N'Учебна марка Boreal', 37.90,1);

    INSERT INTO dbo.Products (CategoryID, BrandID, Name, SKU, Price, Regulated)
    SELECT cat.CategoryID, b.BrandID, x.ProductName, x.SKU, x.Price, x.Regulated
    FROM #SeedProducts AS x
    JOIN dbo.Categories AS cat ON cat.Name = x.CategoryName
    JOIN dbo.Brands AS b ON b.Name = x.BrandName
    WHERE NOT EXISTS (SELECT 1 FROM dbo.Products AS p WHERE p.SKU = x.SKU);

    -- Larger, initially sufficient stock for the coursework demo orders.
    INSERT INTO dbo.Inventory (ProductID, AvailableQuantity)
    SELECT p.ProductID, 600
    FROM #SeedProducts AS x
    JOIN dbo.Products AS p ON p.SKU = x.SKU
    WHERE NOT EXISTS (SELECT 1 FROM dbo.Inventory AS inv WHERE inv.ProductID = p.ProductID);

    /* 4) Seasonal promotions, connected to 7 selected products. */
    ;WITH promo AS (
        SELECT * FROM (VALUES
          (N'Учебна пролет 2026', CONVERT(DECIMAL(5,2),5.00),CONVERT(DATE,'2026-02-01'),CONVERT(DATE,'2026-05-31')),
          (N'Учебно лято 2026',   CONVERT(DECIMAL(5,2),8.00),CONVERT(DATE,'2026-06-01'),CONVERT(DATE,'2026-08-31')),
          (N'Учебна есен 2026',  CONVERT(DECIMAL(5,2),10.00),CONVERT(DATE,'2026-09-01'),CONVERT(DATE,'2026-11-30'))
        ) AS v(Name, DiscountPercentage, StartDate, EndDate)
    )
    INSERT INTO dbo.Promotions (Name, DiscountPercentage, StartDate, EndDate)
    SELECT x.Name, x.DiscountPercentage, x.StartDate, x.EndDate
    FROM promo AS x
    WHERE NOT EXISTS (SELECT 1 FROM dbo.Promotions AS p WHERE p.Name = x.Name);

    INSERT INTO dbo.ProductPromotions (ProductID, PromotionID)
    SELECT p.ProductID, promo.PromotionID
    FROM #SeedProducts AS sp
    JOIN dbo.Products AS p ON p.SKU = sp.SKU
    JOIN dbo.Promotions AS promo ON promo.Name IN
         (N'Учебна пролет 2026', N'Учебно лято 2026', N'Учебна есен 2026')
    WHERE sp.ProductNo IN (1,2,5,10,13,15,19)
      AND NOT EXISTS (
          SELECT 1 FROM dbo.ProductPromotions AS link
          WHERE link.ProductID = p.ProductID AND link.PromotionID = promo.PromotionID
      );

    /* 5) Exactly 150 reproducible order specifications. */
    CREATE TABLE #SeedOrders (
        OrderNo INT NOT NULL PRIMARY KEY,
        ClientNo INT NOT NULL,
        OrderDate DATETIME2(0) NOT NULL,
        DesiredStatus NVARCHAR(30) NOT NULL
    );

    ;WITH seq AS (
        SELECT TOP (150) CONVERT(INT, ROW_NUMBER() OVER (ORDER BY (SELECT NULL))) AS n
        FROM sys.all_objects
    )
    INSERT INTO #SeedOrders (OrderNo, ClientNo, OrderDate, DesiredStatus)
    SELECT n,
           ((n - 1) % 30) + 1,
           DATEADD(MINUTE, 480 + (n * 17) % 600,
               DATEADD(DAY, 2 * (n - 1), CONVERT(DATETIME2(0), '2026-01-15T00:00:00'))),
           CASE n % 10
                WHEN 0 THEN N'Cancelled'
                WHEN 1 THEN N'Pending'
                WHEN 2 THEN N'Pending'
                WHEN 3 THEN N'Processing'
                WHEN 4 THEN N'Processing'
                WHEN 5 THEN N'Processing'
                WHEN 6 THEN N'Processing'
                ELSE N'Completed'
           END
    FROM seq;

    INSERT INTO dbo.Orders
        (CustomerID, ShippingAddressID, OrderDate, Status, TotalPrice)
    SELECT c.CustomerID, a.AddressID, s.OrderDate, N'Pending', 0
    FROM #SeedOrders AS s
    JOIN #SeedCustomers AS sc ON sc.ClientNo = s.ClientNo
    JOIN dbo.Customers AS c ON c.Email = sc.Email
    JOIN dbo.Addresses AS a ON a.CustomerID = c.CustomerID
                             AND a.City = sc.City AND a.Street = sc.Street
    WHERE NOT EXISTS (
        SELECT 1 FROM dbo.Orders AS old
        WHERE old.CustomerID = c.CustomerID AND old.OrderDate = s.OrderDate
    );

    SELECT s.OrderNo, s.DesiredStatus, o.OrderID, o.OrderDate
    INTO #SeedOrderMap
    FROM #SeedOrders AS s
    JOIN #SeedCustomers AS sc ON sc.ClientNo = s.ClientNo
    JOIN dbo.Customers AS c ON c.Email = sc.Email
    JOIN dbo.Orders AS o ON o.CustomerID = c.CustomerID AND o.OrderDate = s.OrderDate;

    IF (SELECT COUNT(*) FROM #SeedOrderMap) <> 150
        THROW 52003, N'Failed to match exactly 150 seed orders.', 1;

    /* 6) One to three distinct product lines per order. Trigger updates total. */
    INSERT INTO dbo.OrderItems
        (OrderID, ProductID, Quantity, UnitPrice, DiscountPercentage)
    SELECT m.OrderID, p.ProductID,
           1 + ((m.OrderNo + slot.SlotNo) % 4),
           p.Price,
           COALESCE(promo.DiscountPercentage, 0)
    FROM #SeedOrderMap AS m
    JOIN dbo.Orders AS o ON o.OrderID = m.OrderID AND o.Status = N'Pending'
    CROSS JOIN (VALUES (1),(2),(3)) AS slot(SlotNo)
    JOIN #SeedProducts AS sp
      ON sp.ProductNo = 1 + ((m.OrderNo * 7 + slot.SlotNo * 5) % 20)
    JOIN dbo.Products AS p ON p.SKU = sp.SKU
    OUTER APPLY (
        SELECT TOP (1) pr.DiscountPercentage
        FROM dbo.ProductPromotions AS link
        JOIN dbo.Promotions AS pr ON pr.PromotionID = link.PromotionID
        WHERE link.ProductID = p.ProductID
          AND CONVERT(DATE, m.OrderDate) BETWEEN pr.StartDate AND pr.EndDate
          AND pr.Name IN (N'Учебна пролет 2026', N'Учебно лято 2026', N'Учебна есен 2026')
        ORDER BY pr.DiscountPercentage DESC, pr.PromotionID
    ) AS promo
    WHERE slot.SlotNo <= 1 + m.OrderNo % 3
      AND NOT EXISTS (
          SELECT 1 FROM dbo.OrderItems AS oi
          WHERE oi.OrderID = m.OrderID AND oi.ProductID = p.ProductID
      );

    /* 7) Simulated permission checks for regulated products in paid orders. */
    INSERT INTO dbo.ComplianceChecks (OrderItemID, RequiredDocs, CheckStatus, CheckDate)
    SELECT oi.OrderItemID,
           N'Само учебна симулация: проверка на разрешителен режим',
           N'Approved', DATEADD(MINUTE, 10, m.OrderDate)
    FROM #SeedOrderMap AS m
    JOIN dbo.OrderItems AS oi ON oi.OrderID = m.OrderID
    JOIN dbo.Products AS p ON p.ProductID = oi.ProductID AND p.Regulated = 1
    WHERE m.DesiredStatus IN (N'Processing', N'Completed')
      AND NOT EXISTS (
          SELECT 1 FROM dbo.ComplianceChecks AS cc
          WHERE cc.OrderItemID = oi.OrderItemID AND cc.CheckStatus = N'Approved'
      );

    /* 8) Successful payments for paid orders, failed attempts for some others. */
    INSERT INTO dbo.Payments (OrderID, Method, Status, Amount, PaymentDate)
    SELECT m.OrderID,
           CASE WHEN m.OrderNo % 3 = 0 THEN N'BankTransfer'
                WHEN m.OrderNo % 3 = 1 THEN N'Card' ELSE N'Prepaid' END,
           N'Succeeded', o.TotalPrice, DATEADD(MINUTE, 20, m.OrderDate)
    FROM #SeedOrderMap AS m
    JOIN dbo.Orders AS o ON o.OrderID = m.OrderID
    WHERE m.DesiredStatus IN (N'Processing', N'Completed')
      AND NOT EXISTS (
          SELECT 1 FROM dbo.Payments AS py
          WHERE py.OrderID = m.OrderID AND py.Status = N'Succeeded'
      );

    INSERT INTO dbo.Payments (OrderID, Method, Status, Amount, PaymentDate)
    SELECT m.OrderID, N'Card', N'Failed', o.TotalPrice,
           DATEADD(MINUTE, 15, m.OrderDate)
    FROM #SeedOrderMap AS m
    JOIN dbo.Orders AS o ON o.OrderID = m.OrderID
    WHERE m.DesiredStatus IN (N'Pending', N'Cancelled')
      AND m.OrderNo % 2 = 0
      AND NOT EXISTS (
          SELECT 1 FROM dbo.Payments AS py
          WHERE py.OrderID = m.OrderID AND py.Status = N'Failed'
      );

    /* 9) Complete paid orders using the existing procedure, including stock. */
    DECLARE @OrderID INT;
    DECLARE @DesiredStatus NVARCHAR(30);

    DECLARE paid_order_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT m.OrderID, m.DesiredStatus
        FROM #SeedOrderMap AS m
        JOIN dbo.Orders AS o ON o.OrderID = m.OrderID
        WHERE m.DesiredStatus IN (N'Processing', N'Completed')
          AND o.Status = N'Pending'
        ORDER BY m.OrderNo;

    OPEN paid_order_cursor;
    FETCH NEXT FROM paid_order_cursor INTO @OrderID, @DesiredStatus;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC dbo.usp_ProcessOrder @OrderID = @OrderID;

        IF @DesiredStatus = N'Completed'
            UPDATE dbo.Orders SET Status = N'Completed' WHERE OrderID = @OrderID;

        FETCH NEXT FROM paid_order_cursor INTO @OrderID, @DesiredStatus;
    END;
    CLOSE paid_order_cursor;
    DEALLOCATE paid_order_cursor;

    UPDATE o SET Status = N'Cancelled'
    FROM dbo.Orders AS o
    JOIN #SeedOrderMap AS m ON m.OrderID = o.OrderID
    WHERE m.DesiredStatus = N'Cancelled' AND o.Status = N'Pending';

    /* 10) Shipments, respecting 0..1 per order. */
    INSERT INTO dbo.Shipments (OrderID, ShippingMethod, Status, ShippingDate)
    SELECT m.OrderID,
           CASE WHEN m.OrderNo % 2 = 0 THEN N'Courier' ELSE N'Pickup' END,
           CASE WHEN m.DesiredStatus = N'Completed' THEN N'Delivered'
                ELSE N'Prepared' END,
           CASE WHEN m.DesiredStatus = N'Completed'
                THEN DATEADD(DAY, 2, m.OrderDate) ELSE NULL END
    FROM #SeedOrderMap AS m
    JOIN dbo.Orders AS o ON o.OrderID = m.OrderID
    WHERE m.DesiredStatus IN (N'Processing', N'Completed')
      AND o.Status IN (N'Processing', N'Completed')
      AND NOT EXISTS (SELECT 1 FROM dbo.Shipments AS s WHERE s.OrderID = m.OrderID);

    COMMIT TRANSACTION;

    DROP TABLE IF EXISTS #SeedOrderMap;
    DROP TABLE IF EXISTS #SeedOrders;
    DROP TABLE IF EXISTS #SeedProducts;
    DROP TABLE IF EXISTS #SeedCustomers;

    PRINT N'Success: 150 stable coursework orders, 30 customers and 20 products prepared.';
END TRY
BEGIN CATCH
    IF CURSOR_STATUS('local', 'paid_order_cursor') >= 0
    BEGIN
        CLOSE paid_order_cursor;
        DEALLOCATE paid_order_cursor;
    END;
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO

/* 11) Optional DWH refresh (does not rebuild old snapshots). */
IF DB_ID(N'GunsBG_DWH') IS NOT NULL
   AND OBJECT_ID(N'GunsBG_DWH.dbo.usp_LoadGunsBG_DWH', N'P') IS NOT NULL
BEGIN
    EXEC GunsBG_DWH.dbo.usp_LoadGunsBG_DWH;
    PRINT N'DWH refresh complete.';
END
ELSE
    PRINT N'DWH ETL not installed; run GunsBG_ETL_fixed.sql later.';
GO

/* 12) Verification: 150 seeded orders and their distribution. */
USE GunsBG;
GO
SELECT COUNT(*) AS SeedOrders,
       MIN(o.OrderDate) AS FirstOrderDate,
       MAX(o.OrderDate) AS LastOrderDate
FROM dbo.Orders AS o
JOIN dbo.Customers AS c ON c.CustomerID = o.CustomerID
WHERE c.Email LIKE N'gunsbg.seed26.%@example.test'
  AND o.OrderDate >= '2026-01-15' AND o.OrderDate < '2026-11-11';

SELECT o.Status, COUNT(*) AS OrderCount
FROM dbo.Orders AS o
JOIN dbo.Customers AS c ON c.CustomerID = o.CustomerID
WHERE c.Email LIKE N'gunsbg.seed26.%@example.test'
  AND o.OrderDate >= '2026-01-15' AND o.OrderDate < '2026-11-11'
GROUP BY o.Status
ORDER BY o.Status;

SELECT COUNT(*) AS SeedCustomers
FROM dbo.Customers WHERE Email LIKE N'gunsbg.seed26.%@example.test';

SELECT COUNT(*) AS SeedProducts
FROM dbo.Products WHERE SKU LIKE N'EDU26-%';
GO

IF DB_ID(N'GunsBG_DWH') IS NOT NULL
   AND OBJECT_ID(N'GunsBG_DWH.dbo.FactOrders', N'U') IS NOT NULL
BEGIN
    SELECT N'FactSales' AS TableName, COUNT(*) AS TotalRows FROM GunsBG_DWH.dbo.FactSales
    UNION ALL SELECT N'FactOrders', COUNT(*) FROM GunsBG_DWH.dbo.FactOrders
    UNION ALL SELECT N'FactInventory', COUNT(*) FROM GunsBG_DWH.dbo.FactInventory;
END;
GO
