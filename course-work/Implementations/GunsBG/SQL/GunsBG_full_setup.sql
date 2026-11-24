/*
    Guns.bg | Coursework | Microsoft SQL Server
    Complete relational database: 13 tables + demonstration data
    1 scalar function, 1 trigger, 2 stored procedures

    Safe for an existing GunsBG database: DOES NOT DROP tables or data.
    Existing tables are kept unchanged; missing tables are created.
    Run the entire script in SSMS (New Query -> Execute).

    NOTE: This is an educational model, not the real Guns.bg database.
*/

-- 0. Database
IF DB_ID(N'GunsBG') IS NULL
    EXEC(N'CREATE DATABASE GunsBG');
GO
USE GunsBG;
GO

-- 1. CUSTOMERS
IF OBJECT_ID(N'dbo.Customers', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Customers (
        CustomerID INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        Name NVARCHAR(100) NOT NULL,
        Email NVARCHAR(150) NOT NULL UNIQUE,
        Phone NVARCHAR(20) NULL
    );
END;
GO

-- 2. ADDRESSES
IF OBJECT_ID(N'dbo.Addresses', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Addresses (
        AddressID INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        CustomerID INT NOT NULL,
        City NVARCHAR(100) NOT NULL,
        Street NVARCHAR(200) NOT NULL,
        PostCode NVARCHAR(10) NOT NULL,
        CONSTRAINT FK_Addresses_Customers FOREIGN KEY (CustomerID)
            REFERENCES dbo.Customers(CustomerID)
    );
END;
GO

-- 3. CATEGORIES
IF OBJECT_ID(N'dbo.Categories', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Categories (
        CategoryID INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        Name NVARCHAR(100) NOT NULL
    );
END;
GO

-- 4. BRANDS
IF OBJECT_ID(N'dbo.Brands', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Brands (
        BrandID INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        Name NVARCHAR(100) NOT NULL
    );
END;
GO

-- 5. PRODUCTS
IF OBJECT_ID(N'dbo.Products', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Products (
        ProductID INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        CategoryID INT NOT NULL,
        BrandID INT NOT NULL,
        Name NVARCHAR(150) NOT NULL,
        SKU NVARCHAR(50) NOT NULL UNIQUE,
        Price DECIMAL(12,2) NOT NULL,
        Regulated BIT NOT NULL CONSTRAINT DF_Products_Regulated DEFAULT (0),
        CONSTRAINT FK_Products_Categories FOREIGN KEY (CategoryID)
            REFERENCES dbo.Categories(CategoryID),
        CONSTRAINT FK_Products_Brands FOREIGN KEY (BrandID)
            REFERENCES dbo.Brands(BrandID),
        CONSTRAINT CHK_Products_Price CHECK (Price >= 0)
    );
END;
GO

-- 6. INVENTORY: one inventory row per product
IF OBJECT_ID(N'dbo.Inventory', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Inventory (
        InventoryID INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        ProductID INT NOT NULL,
        AvailableQuantity INT NOT NULL
            CONSTRAINT DF_Inventory_Quantity DEFAULT (0),
        CONSTRAINT FK_Inventory_Products FOREIGN KEY (ProductID)
            REFERENCES dbo.Products(ProductID),
        CONSTRAINT UQ_Inventory_Product UNIQUE (ProductID),
        CONSTRAINT CHK_Inventory_Quantity CHECK (AvailableQuantity >= 0)
    );
END;
GO

-- 7. ORDERS
IF OBJECT_ID(N'dbo.Orders', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Orders (
        OrderID INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        CustomerID INT NOT NULL,
        ShippingAddressID INT NOT NULL,
        OrderDate DATETIME2(0) NOT NULL
            CONSTRAINT DF_Orders_OrderDate DEFAULT (SYSDATETIME()),
        Status NVARCHAR(30) NOT NULL
            CONSTRAINT DF_Orders_Status DEFAULT (N'Pending'),
        TotalPrice DECIMAL(12,2) NOT NULL
            CONSTRAINT DF_Orders_TotalPrice DEFAULT (0),
        CONSTRAINT FK_Orders_Customers FOREIGN KEY (CustomerID)
            REFERENCES dbo.Customers(CustomerID),
        CONSTRAINT FK_Orders_Addresses FOREIGN KEY (ShippingAddressID)
            REFERENCES dbo.Addresses(AddressID),
        CONSTRAINT CHK_Orders_TotalPrice CHECK (TotalPrice >= 0),
        CONSTRAINT CHK_Orders_Status CHECK
            (Status IN (N'Pending', N'Processing', N'Completed', N'Cancelled'))
    );
END;
GO

-- 8. ORDERITEMS: resolves Orders <-> Products (M:N)
IF OBJECT_ID(N'dbo.OrderItems', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.OrderItems (
        OrderItemID INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        OrderID INT NOT NULL,
        ProductID INT NOT NULL,
        Quantity INT NOT NULL,
        UnitPrice DECIMAL(12,2) NOT NULL,
        DiscountPercentage DECIMAL(5,2) NOT NULL
            CONSTRAINT DF_OrderItems_Discount DEFAULT (0),
        CONSTRAINT FK_OrderItems_Orders FOREIGN KEY (OrderID)
            REFERENCES dbo.Orders(OrderID),
        CONSTRAINT FK_OrderItems_Products FOREIGN KEY (ProductID)
            REFERENCES dbo.Products(ProductID),
        CONSTRAINT UQ_OrderItems_Order_Product UNIQUE (OrderID, ProductID),
        CONSTRAINT CHK_OrderItems_Quantity CHECK (Quantity > 0),
        CONSTRAINT CHK_OrderItems_UnitPrice CHECK (UnitPrice >= 0),
        CONSTRAINT CHK_OrderItems_Discount CHECK
            (DiscountPercentage BETWEEN 0 AND 100)
    );
END;
GO

-- 9. PAYMENTS: an order can have several payment attempts
IF OBJECT_ID(N'dbo.Payments', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Payments (
        PaymentID INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        OrderID INT NOT NULL,
        Method NVARCHAR(40) NOT NULL,
        Status NVARCHAR(30) NOT NULL,
        Amount DECIMAL(12,2) NOT NULL,
        PaymentDate DATETIME2(0) NULL,
        CONSTRAINT FK_Payments_Orders FOREIGN KEY (OrderID)
            REFERENCES dbo.Orders(OrderID),
        CONSTRAINT CHK_Payments_Amount CHECK (Amount >= 0),
        CONSTRAINT CHK_Payments_Status CHECK
            (Status IN (N'Pending', N'Succeeded', N'Failed', N'Refunded'))
    );
END;
GO

-- 10. SHIPMENTS: an order may have zero or one shipment
IF OBJECT_ID(N'dbo.Shipments', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Shipments (
        ShipmentID INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        OrderID INT NOT NULL,
        ShippingMethod NVARCHAR(50) NOT NULL,
        Status NVARCHAR(30) NOT NULL,
        ShippingDate DATETIME2(0) NULL,
        CONSTRAINT FK_Shipments_Orders FOREIGN KEY (OrderID)
            REFERENCES dbo.Orders(OrderID),
        CONSTRAINT UQ_Shipments_Order UNIQUE (OrderID)
    );
END;
GO

-- 11. PROMOTIONS
IF OBJECT_ID(N'dbo.Promotions', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Promotions (
        PromotionID INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        Name NVARCHAR(120) NOT NULL,
        DiscountPercentage DECIMAL(5,2) NOT NULL,
        StartDate DATE NOT NULL,
        EndDate DATE NOT NULL,
        CONSTRAINT CHK_Promotions_Discount CHECK
            (DiscountPercentage BETWEEN 0 AND 100),
        CONSTRAINT CHK_Promotions_Dates CHECK (EndDate >= StartDate)
    );
END;
GO

-- 12. PRODUCTPROMOTIONS: resolves Products <-> Promotions (M:N)
IF OBJECT_ID(N'dbo.ProductPromotions', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ProductPromotions (
        ProductID INT NOT NULL,
        PromotionID INT NOT NULL,
        CONSTRAINT PK_ProductPromotions PRIMARY KEY (ProductID, PromotionID),
        CONSTRAINT FK_ProductPromotions_Products FOREIGN KEY (ProductID)
            REFERENCES dbo.Products(ProductID),
        CONSTRAINT FK_ProductPromotions_Promotions FOREIGN KEY (PromotionID)
            REFERENCES dbo.Promotions(PromotionID)
    );
END;
GO

-- 13. COMPLIANCECHECKS: checks for regulated order items
IF OBJECT_ID(N'dbo.ComplianceChecks', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ComplianceChecks (
        CheckID INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        OrderItemID INT NOT NULL,
        RequiredDocs NVARCHAR(250) NOT NULL,
        CheckStatus NVARCHAR(30) NOT NULL
            CONSTRAINT DF_ComplianceChecks_Status DEFAULT (N'Pending'),
        CheckDate DATETIME2(0) NULL,
        CONSTRAINT FK_ComplianceChecks_OrderItems FOREIGN KEY (OrderItemID)
            REFERENCES dbo.OrderItems(OrderItemID),
        CONSTRAINT CHK_ComplianceChecks_Status CHECK
            (CheckStatus IN (N'Pending', N'Approved', N'Rejected'))
    );
END;
GO

-- 14. SCALAR FUNCTION: calculates the current sum of order lines
CREATE OR ALTER FUNCTION dbo.fn_OrderTotal (@OrderID INT)
RETURNS DECIMAL(12,2)
AS
BEGIN
    DECLARE @Total DECIMAL(12,2);

    SELECT @Total = COALESCE(
        SUM(CAST(ROUND(
            Quantity * UnitPrice * (1 - DiscountPercentage / 100.0), 2
        ) AS DECIMAL(12,2))), 0)
    FROM dbo.OrderItems
    WHERE OrderID = @OrderID;

    RETURN @Total;
END;
GO

-- 15. TRIGGER: recalculates the order total when lines change
CREATE OR ALTER TRIGGER dbo.trg_OrderItems_RecalculateTotal
ON dbo.OrderItems
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    -- Do not silently change already-processed orders.
    IF EXISTS (
        SELECT 1
        FROM (
            SELECT OrderID FROM inserted
            UNION
            SELECT OrderID FROM deleted
        ) AS changed
        INNER JOIN dbo.Orders AS o ON o.OrderID = changed.OrderID
        WHERE o.Status <> N'Pending'
    )
    BEGIN
        THROW 50010, N'Order items can only be changed while the order is Pending.', 1;
    END;

    ;WITH ChangedOrders AS (
        SELECT OrderID FROM inserted
        UNION
        SELECT OrderID FROM deleted
    )
    UPDATE o
       SET TotalPrice = dbo.fn_OrderTotal(o.OrderID)
    FROM dbo.Orders AS o
    INNER JOIN ChangedOrders AS c ON c.OrderID = o.OrderID;
END;
GO

-- Synchronize totals of preexisting pending orders (if any)
UPDATE o
   SET TotalPrice = dbo.fn_OrderTotal(o.OrderID)
FROM dbo.Orders AS o
WHERE o.Status = N'Pending';
GO

-- 16. PROCEDURE: create an order only with an address owned by its customer
CREATE OR ALTER PROCEDURE dbo.usp_CreateOrder
    @CustomerID INT,
    @ShippingAddressID INT,
    @NewOrderID INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1 FROM dbo.Customers WHERE CustomerID = @CustomerID
    )
        THROW 50020, N'Customer does not exist.', 1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.Addresses
        WHERE AddressID = @ShippingAddressID
          AND CustomerID = @CustomerID
    )
        THROW 50021, N'Shipping address does not belong to the customer.', 1;

    INSERT INTO dbo.Orders (CustomerID, ShippingAddressID)
    VALUES (@CustomerID, @ShippingAddressID);

    SET @NewOrderID = CONVERT(INT, SCOPE_IDENTITY());
END;
GO

-- 17. PROCEDURE: confirm payment and legal checks, then decrease stock
CREATE OR ALTER PROCEDURE dbo.usp_ProcessOrder
    @OrderID INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @CurrentStatus NVARCHAR(30);
    DECLARE @OrderTotal DECIMAL(12,2);
    DECLARE @RequiredProductCount INT;
    DECLARE @UpdatedProductCount INT;

    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT @CurrentStatus = Status, @OrderTotal = TotalPrice
        FROM dbo.Orders WITH (UPDLOCK, HOLDLOCK)
        WHERE OrderID = @OrderID;

        IF @CurrentStatus IS NULL
            THROW 50030, N'Order does not exist.', 1;

        IF @CurrentStatus <> N'Pending'
            THROW 50031, N'Only Pending orders can be processed.', 1;

        IF NOT EXISTS (
            SELECT 1 FROM dbo.OrderItems WHERE OrderID = @OrderID
        )
            THROW 50032, N'Order must contain at least one item.', 1;

        -- Educational rule: require sufficient successful payment before processing.
        IF COALESCE((
            SELECT SUM(Amount)
            FROM dbo.Payments
            WHERE OrderID = @OrderID AND Status = N'Succeeded'
        ), 0) < @OrderTotal
            THROW 50033, N'Order has not been paid successfully.', 1;

        -- Regulated items require an Approved compliance check.
        IF EXISTS (
            SELECT 1
            FROM dbo.OrderItems AS oi
            INNER JOIN dbo.Products AS p ON p.ProductID = oi.ProductID
            WHERE oi.OrderID = @OrderID
              AND p.Regulated = 1
              AND NOT EXISTS (
                  SELECT 1
                  FROM dbo.ComplianceChecks AS cc
                  WHERE cc.OrderItemID = oi.OrderItemID
                    AND cc.CheckStatus = N'Approved'
              )
        )
            THROW 50034, N'Regulated product requires an approved check.', 1;

        SELECT @RequiredProductCount = COUNT(DISTINCT ProductID)
        FROM dbo.OrderItems
        WHERE OrderID = @OrderID;

        ;WITH RequiredProducts AS (
            SELECT ProductID, SUM(Quantity) AS RequiredQty
            FROM dbo.OrderItems
            WHERE OrderID = @OrderID
            GROUP BY ProductID
        )
        UPDATE inv
           SET AvailableQuantity = inv.AvailableQuantity - rp.RequiredQty
        FROM dbo.Inventory AS inv
        INNER JOIN RequiredProducts AS rp ON rp.ProductID = inv.ProductID
        WHERE inv.AvailableQuantity >= rp.RequiredQty;

        SET @UpdatedProductCount = @@ROWCOUNT;

        IF @UpdatedProductCount <> @RequiredProductCount
            THROW 50035, N'Insufficient stock or missing inventory row.', 1;

        UPDATE dbo.Orders
           SET Status = N'Processing'
        WHERE OrderID = @OrderID;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

-- 18. SAMPLE DATA (idempotent: avoids duplicating this demo)
IF NOT EXISTS (SELECT 1 FROM dbo.Categories WHERE Name = N'Ловна екипировка')
    INSERT INTO dbo.Categories (Name) VALUES (N'Ловна екипировка');
IF NOT EXISTS (SELECT 1 FROM dbo.Categories WHERE Name = N'Оптика')
    INSERT INTO dbo.Categories (Name) VALUES (N'Оптика');
IF NOT EXISTS (SELECT 1 FROM dbo.Categories WHERE Name = N'Боеприпаси')
    INSERT INTO dbo.Categories (Name) VALUES (N'Боеприпаси');

IF NOT EXISTS (SELECT 1 FROM dbo.Brands WHERE Name = N'Demo Outdoor')
    INSERT INTO dbo.Brands (Name) VALUES (N'Demo Outdoor');
IF NOT EXISTS (SELECT 1 FROM dbo.Brands WHERE Name = N'Demo Optics')
    INSERT INTO dbo.Brands (Name) VALUES (N'Demo Optics');
GO

IF NOT EXISTS (SELECT 1 FROM dbo.Customers WHERE Email = N'demo.gunsbg@example.test')
    INSERT INTO dbo.Customers (Name, Email, Phone)
    VALUES (N'Демо клиент', N'demo.gunsbg@example.test', N'0888000000');

DECLARE @CustomerID INT = (
    SELECT CustomerID FROM dbo.Customers WHERE Email = N'demo.gunsbg@example.test'
);

IF NOT EXISTS (
    SELECT 1 FROM dbo.Addresses
    WHERE CustomerID = @CustomerID AND City = N'Пловдив'
      AND Street = N'ул. Примерна 1'
)
    INSERT INTO dbo.Addresses (CustomerID, City, Street, PostCode)
    VALUES (@CustomerID, N'Пловдив', N'ул. Примерна 1', N'4000');
GO

IF NOT EXISTS (SELECT 1 FROM dbo.Products WHERE SKU = N'DEMO-JACKET-01')
    INSERT INTO dbo.Products (CategoryID, BrandID, Name, SKU, Price, Regulated)
    SELECT c.CategoryID, b.BrandID, N'Ловно яке (демо)', N'DEMO-JACKET-01', 129.90, 0
    FROM dbo.Categories AS c CROSS JOIN dbo.Brands AS b
    WHERE c.Name = N'Ловна екипировка' AND b.Name = N'Demo Outdoor';

IF NOT EXISTS (SELECT 1 FROM dbo.Products WHERE SKU = N'DEMO-OPTICS-01')
    INSERT INTO dbo.Products (CategoryID, BrandID, Name, SKU, Price, Regulated)
    SELECT c.CategoryID, b.BrandID, N'Оптика (демо)', N'DEMO-OPTICS-01', 249.00, 0
    FROM dbo.Categories AS c CROSS JOIN dbo.Brands AS b
    WHERE c.Name = N'Оптика' AND b.Name = N'Demo Optics';

IF NOT EXISTS (SELECT 1 FROM dbo.Products WHERE SKU = N'DEMO-AMMO-01')
    INSERT INTO dbo.Products (CategoryID, BrandID, Name, SKU, Price, Regulated)
    SELECT c.CategoryID, b.BrandID, N'Боеприпаси (демо)', N'DEMO-AMMO-01', 19.90, 1
    FROM dbo.Categories AS c CROSS JOIN dbo.Brands AS b
    WHERE c.Name = N'Боеприпаси' AND b.Name = N'Demo Outdoor';
GO

-- Inventory rows for products which don't already have one.
INSERT INTO dbo.Inventory (ProductID, AvailableQuantity)
SELECT p.ProductID,
       CASE p.SKU
           WHEN N'DEMO-JACKET-01' THEN 20
           WHEN N'DEMO-OPTICS-01' THEN 12
           WHEN N'DEMO-AMMO-01' THEN 50
           ELSE 0
       END
FROM dbo.Products AS p
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.Inventory AS inv WHERE inv.ProductID = p.ProductID
);
GO

IF NOT EXISTS (SELECT 1 FROM dbo.Promotions WHERE Name = N'Демо промоция 10%')
    INSERT INTO dbo.Promotions
        (Name, DiscountPercentage, StartDate, EndDate)
    VALUES (N'Демо промоция 10%', 10, '2026-01-01', '2027-12-31');

INSERT INTO dbo.ProductPromotions (ProductID, PromotionID)
SELECT p.ProductID, promo.PromotionID
FROM dbo.Products AS p
CROSS JOIN dbo.Promotions AS promo
WHERE p.SKU = N'DEMO-JACKET-01'
  AND promo.Name = N'Демо промоция 10%'
  AND NOT EXISTS (
      SELECT 1 FROM dbo.ProductPromotions AS pp
      WHERE pp.ProductID = p.ProductID
        AND pp.PromotionID = promo.PromotionID
  );
GO

DECLARE @DemoCustomerID INT;
DECLARE @DemoAddressID INT;
DECLARE @DemoOrderID INT;
DECLARE @JacketID INT;
DECLARE @AmmoID INT;
DECLARE @AmmoOrderItemID INT;

SELECT @DemoCustomerID = CustomerID
FROM dbo.Customers WHERE Email = N'demo.gunsbg@example.test';

SELECT TOP (1) @DemoAddressID = AddressID
FROM dbo.Addresses
WHERE CustomerID = @DemoCustomerID AND City = N'Пловдив'
  AND Street = N'ул. Примерна 1'
ORDER BY AddressID;

SELECT @JacketID = ProductID FROM dbo.Products WHERE SKU = N'DEMO-JACKET-01';
SELECT @AmmoID = ProductID FROM dbo.Products WHERE SKU = N'DEMO-AMMO-01';

SELECT TOP (1) @DemoOrderID = OrderID
FROM dbo.Orders
WHERE CustomerID = @DemoCustomerID
ORDER BY OrderID;

IF @DemoOrderID IS NULL
    EXEC dbo.usp_CreateOrder
        @CustomerID = @DemoCustomerID,
        @ShippingAddressID = @DemoAddressID,
        @NewOrderID = @DemoOrderID OUTPUT;

-- Do not modify an already processed order on reruns.
IF EXISTS (
    SELECT 1 FROM dbo.Orders
    WHERE OrderID = @DemoOrderID AND Status = N'Pending'
)
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM dbo.OrderItems
        WHERE OrderID = @DemoOrderID AND ProductID = @JacketID
    )
        INSERT INTO dbo.OrderItems
            (OrderID, ProductID, Quantity, UnitPrice, DiscountPercentage)
        SELECT @DemoOrderID, ProductID, 2, Price, 10
        FROM dbo.Products WHERE ProductID = @JacketID;

    IF NOT EXISTS (
        SELECT 1 FROM dbo.OrderItems
        WHERE OrderID = @DemoOrderID AND ProductID = @AmmoID
    )
        INSERT INTO dbo.OrderItems
            (OrderID, ProductID, Quantity, UnitPrice, DiscountPercentage)
        SELECT @DemoOrderID, ProductID, 1, Price, 0
        FROM dbo.Products WHERE ProductID = @AmmoID;

    SELECT @AmmoOrderItemID = OrderItemID
    FROM dbo.OrderItems
    WHERE OrderID = @DemoOrderID AND ProductID = @AmmoID;

    IF @AmmoOrderItemID IS NOT NULL
       AND NOT EXISTS (
           SELECT 1 FROM dbo.ComplianceChecks
           WHERE OrderItemID = @AmmoOrderItemID AND CheckStatus = N'Approved'
       )
        INSERT INTO dbo.ComplianceChecks
            (OrderItemID, RequiredDocs, CheckStatus, CheckDate)
        VALUES (@AmmoOrderItemID,
                N'Демо: проверка за необходимото разрешение',
                N'Approved', SYSDATETIME());

    IF NOT EXISTS (
        SELECT 1 FROM dbo.Payments
        WHERE OrderID = @DemoOrderID AND Status = N'Succeeded'
    )
        INSERT INTO dbo.Payments
            (OrderID, Method, Status, Amount, PaymentDate)
        VALUES (@DemoOrderID, N'Card', N'Succeeded',
                dbo.fn_OrderTotal(@DemoOrderID), SYSDATETIME());

    EXEC dbo.usp_ProcessOrder @OrderID = @DemoOrderID;
END;

IF NOT EXISTS (SELECT 1 FROM dbo.Shipments WHERE OrderID = @DemoOrderID)
    INSERT INTO dbo.Shipments (OrderID, ShippingMethod, Status, ShippingDate)
    VALUES (@DemoOrderID, N'Courier', N'Prepared', NULL);
GO

-- 19. VERIFICATION
PRINT N'=== Tables in GunsBG ===';
SELECT TABLE_NAME
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'dbo' AND TABLE_TYPE = 'BASE TABLE'
ORDER BY TABLE_NAME;

PRINT N'=== Sample order and function result ===';
SELECT o.OrderID, c.Name AS CustomerName, o.Status,
       o.TotalPrice, dbo.fn_OrderTotal(o.OrderID) AS RecalculatedTotal
FROM dbo.Orders AS o
JOIN dbo.Customers AS c ON c.CustomerID = o.CustomerID
WHERE c.Email = N'demo.gunsbg@example.test';

PRINT N'=== Sample inventory ===';
SELECT p.SKU, p.Name AS ProductName, i.AvailableQuantity
FROM dbo.Inventory AS i
JOIN dbo.Products AS p ON p.ProductID = i.ProductID
WHERE p.SKU LIKE N'DEMO-%'
ORDER BY p.SKU;

PRINT N'=== Stored procedures, function and trigger ===';
SELECT name, type_desc
FROM sys.objects
WHERE name IN (
    N'usp_CreateOrder', N'usp_ProcessOrder',
    N'fn_OrderTotal', N'trg_OrderItems_RecalculateTotal'
)
ORDER BY name;
GO
