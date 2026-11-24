/*
    Guns.bg Coursework | Physical Data Warehouse (SQL Server)
    Source OLTP: GunsBG (dbo)
    Target DWH: GunsBG_DWH (dbo)

    Aligned with GunsBG_DataWarehouse_UML.drawio:
      Facts:      FactSales, FactOrders, FactInventory
      Dimensions: DimDate, DimCustomer, DimProduct, DimCategory,
                  DimBrand, DimPayment, DimShipment

    Run AFTER GunsBG_full_setup.sql.
    Safe to re-run: does not drop existing tables or data.
    This script creates schema only. Run GunsBG_ETL.sql afterward.
*/

IF DB_ID(N'GunsBG_DWH') IS NULL
    EXEC(N'CREATE DATABASE GunsBG_DWH');
GO
USE GunsBG_DWH;
GO

-- DIMENSIONS (load order: independent dimensions before DimProduct)
IF OBJECT_ID(N'dbo.DimDate', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.DimDate (
        DateKey INT NOT NULL PRIMARY KEY,      -- YYYYMMDD, e.g. 20261123
        FullDate DATE NOT NULL UNIQUE,
        DayNumber TINYINT NOT NULL,
        MonthNumber TINYINT NOT NULL,
        QuarterNumber TINYINT NOT NULL,
        YearNumber SMALLINT NOT NULL,
        CONSTRAINT CK_DimDate_Day CHECK (DayNumber BETWEEN 1 AND 31),
        CONSTRAINT CK_DimDate_Month CHECK (MonthNumber BETWEEN 1 AND 12),
        CONSTRAINT CK_DimDate_Quarter CHECK (QuarterNumber BETWEEN 1 AND 4)
    );
END;
GO

IF OBJECT_ID(N'dbo.DimCustomer', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.DimCustomer (
        CustomerKey INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        CustomerID INT NOT NULL UNIQUE,        -- OLTP business key
        CustomerName NVARCHAR(100) NOT NULL,
        Email NVARCHAR(150) NOT NULL
    );
END;
GO

IF OBJECT_ID(N'dbo.DimCategory', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.DimCategory (
        CategoryKey INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        CategoryID INT NOT NULL UNIQUE,
        CategoryName NVARCHAR(100) NOT NULL
    );
END;
GO

IF OBJECT_ID(N'dbo.DimBrand', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.DimBrand (
        BrandKey INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        BrandID INT NOT NULL UNIQUE,
        BrandName NVARCHAR(100) NOT NULL
    );
END;
GO

-- Snowflake: DimProduct references DimCategory and DimBrand.
IF OBJECT_ID(N'dbo.DimProduct', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.DimProduct (
        ProductKey INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        ProductID INT NOT NULL UNIQUE,
        CategoryKey INT NOT NULL,
        BrandKey INT NOT NULL,
        ProductName NVARCHAR(150) NOT NULL,
        SKU NVARCHAR(50) NOT NULL,
        Regulated BIT NOT NULL,
        CONSTRAINT FK_DimProduct_Category FOREIGN KEY (CategoryKey)
            REFERENCES dbo.DimCategory(CategoryKey),
        CONSTRAINT FK_DimProduct_Brand FOREIGN KEY (BrandKey)
            REFERENCES dbo.DimBrand(BrandKey)
    );
END;
GO

IF OBJECT_ID(N'dbo.DimPayment', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.DimPayment (
        PaymentKey INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        Method NVARCHAR(50) NOT NULL,
        Status NVARCHAR(30) NOT NULL,
        CONSTRAINT UQ_DimPayment_Method_Status UNIQUE (Method, Status)
    );
END;
GO

IF OBJECT_ID(N'dbo.DimShipment', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.DimShipment (
        ShipmentKey INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        ShippingMethod NVARCHAR(50) NOT NULL,
        Status NVARCHAR(30) NOT NULL,
        CONSTRAINT UQ_DimShipment_Method_Status UNIQUE (ShippingMethod, Status)
    );
END;
GO

-- FACTS
-- Grain: one eligible paid/processed order line (OrderItemID).
IF OBJECT_ID(N'dbo.FactSales', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.FactSales (
        SalesKey BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        DateKey INT NOT NULL,
        CustomerKey INT NOT NULL,
        ProductKey INT NOT NULL,
        OrderItemID INT NOT NULL UNIQUE,       -- OLTP line identifier
        OrderID INT NOT NULL,                  -- OLTP order identifier
        Quantity INT NOT NULL,
        UnitPrice DECIMAL(12,2) NOT NULL,
        DiscountPercentage DECIMAL(5,2) NOT NULL,
        SalesAmount DECIMAL(12,2) NOT NULL,
        CONSTRAINT FK_FactSales_Date FOREIGN KEY (DateKey)
            REFERENCES dbo.DimDate(DateKey),
        CONSTRAINT FK_FactSales_Customer FOREIGN KEY (CustomerKey)
            REFERENCES dbo.DimCustomer(CustomerKey),
        CONSTRAINT FK_FactSales_Product FOREIGN KEY (ProductKey)
            REFERENCES dbo.DimProduct(ProductKey),
        CONSTRAINT CK_FactSales_Quantity CHECK (Quantity > 0),
        CONSTRAINT CK_FactSales_Price CHECK (UnitPrice >= 0),
        CONSTRAINT CK_FactSales_Discount CHECK (DiscountPercentage BETWEEN 0 AND 100),
        CONSTRAINT CK_FactSales_Amount CHECK (SalesAmount >= 0)
    );
END;
GO

-- Grain: one OLTP order; latest payment attempt and current shipment state.
IF OBJECT_ID(N'dbo.FactOrders', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.FactOrders (
        OrderKey BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        DateKey INT NOT NULL,
        CustomerKey INT NOT NULL,
        PaymentKey INT NOT NULL,
        ShipmentKey INT NOT NULL,
        OrderID INT NOT NULL UNIQUE,           -- OLTP business key
        OrderStatus NVARCHAR(30) NOT NULL,
        OrderTotal DECIMAL(12,2) NOT NULL,
        LineItemCount INT NOT NULL,
        TotalQuantity INT NOT NULL,
        CONSTRAINT FK_FactOrders_Date FOREIGN KEY (DateKey)
            REFERENCES dbo.DimDate(DateKey),
        CONSTRAINT FK_FactOrders_Customer FOREIGN KEY (CustomerKey)
            REFERENCES dbo.DimCustomer(CustomerKey),
        CONSTRAINT FK_FactOrders_Payment FOREIGN KEY (PaymentKey)
            REFERENCES dbo.DimPayment(PaymentKey),
        CONSTRAINT FK_FactOrders_Shipment FOREIGN KEY (ShipmentKey)
            REFERENCES dbo.DimShipment(ShipmentKey),
        CONSTRAINT CK_FactOrders_Total CHECK (OrderTotal >= 0),
        CONSTRAINT CK_FactOrders_Lines CHECK (LineItemCount >= 0),
        CONSTRAINT CK_FactOrders_Quantity CHECK (TotalQuantity >= 0)
    );
END;
GO

-- Grain: one product's stock at the date of an ETL run.
IF OBJECT_ID(N'dbo.FactInventory', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.FactInventory (
        InventoryKey BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        DateKey INT NOT NULL,
        ProductKey INT NOT NULL,
        AvailableQuantity INT NOT NULL,
        CONSTRAINT FK_FactInventory_Date FOREIGN KEY (DateKey)
            REFERENCES dbo.DimDate(DateKey),
        CONSTRAINT FK_FactInventory_Product FOREIGN KEY (ProductKey)
            REFERENCES dbo.DimProduct(ProductKey),
        CONSTRAINT UQ_FactInventory_Date_Product UNIQUE (DateKey, ProductKey),
        CONSTRAINT CK_FactInventory_Quantity CHECK (AvailableQuantity >= 0)
    );
END;
GO

-- Sanity check of the 10 expected tables.
SELECT TABLE_NAME
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'dbo' AND TABLE_TYPE = 'BASE TABLE'
ORDER BY TABLE_NAME;
GO
