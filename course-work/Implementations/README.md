# Guns.bg — Реализация на курсова работа

**Дисциплина:** Софтуерно моделиране и анализ  
**Студент:** Тайлян Такев  
**Факултетен номер:** 2401321045  
**Тема:** Моделиране и анализ на данните на онлайн магазина Guns.bg

## 1. Описание на проекта

Проектът представя модел на информационна система за **онлайн магазина Guns.bg**, с фокус върху съхранението, обработката и анализа на данни за клиенти, продукти, поръчки, плащания, доставки и наличности. Не се разглеждат физически магазини, стрелбища или други услуги извън електронната търговия.

Реализацията включва релационна база данни **GunsBG** в Microsoft SQL Server, концептуална и логическа ER диаграма, Data Warehouse **GunsBG_DWH**, ETL процес и аналитичен отчет в Power BI Desktop.

Подробните бизнес изисквания са описани в [GunsBG.md](../GunsBG.md).

## 2. Използвани технологии

- **Microsoft SQL Server / T-SQL** — релационна база данни, процедури, функция, тригер и Data Warehouse.
- **SQL Server Management Studio (SSMS)** — изпълнение и проверка на SQL скриптовете.
- **diagrams.net (draw.io)** — концептуална ER диаграма (Chen), логическа ER диаграма (Crow’s Foot) и физически модел на Data Warehouse (UML Database Notation).
- **Power BI Desktop** — модел на данните, DAX мерки, визуализации и интерактивни филтри.

## 3. Структура на файловете

```text
course-work/
├── GunsBG.md
└── implementations/
    ├── README.md
    └── GunsBG/
        ├── diagrams/
        │   ├── Conceptual.drawio
        │   ├── Logical.drawio
        │   └── DataWarehouse.drawio
        ├── sql/
        │   ├── GunsBG_full_setup.sql
        │   ├── GunsBG_SeedData.sql
        │   ├── GunsBG_DWH.sql
        │   └── GunsBG_ETL.sql
        └── powerbi/
            └── GunsBG_Report.pbix
```

*Имената на файловете в горната структура трябва да съвпадат с действително качените файлове.*

## 4. Структура на базите данни

### Релационна база данни — GunsBG

Съдържа **13 таблици**: `Customers`, `Addresses`, `Categories`, `Brands`, `Products`, `Inventory`, `Orders`, `OrderItems`, `Payments`, `Shipments`, `Promotions`, `ProductPromotions` и `ComplianceChecks`.

Реализирани са:

- съхранени процедури `usp_CreateOrder` и `usp_ProcessOrder`;
- функция `fn_OrderTotal`;
- тригер `trg_OrderItems_RecalculateTotal`;
- тестови данни за клиенти, продукти, поръчки и свързаните с тях записи.

### Data Warehouse — GunsBG_DWH

Съдържа **3 факт таблици** — `FactSales`, `FactOrders`, `FactInventory`, и **7 таблици измерения** — `DimDate`, `DimCustomer`, `DimProduct`, `DimCategory`, `DimBrand`, `DimPayment`, `DimShipment`.

ETL зареждането се извършва чрез процедурата `dbo.usp_LoadGunsBG_DWH`.

## 5. Инсталация и стартиране

### Необходими програми

1. Microsoft SQL Server с работеща локална или достъпна инстанция.
2. SQL Server Management Studio (SSMS).
3. Power BI Desktop.
4. diagrams.net (по желание, за преглед или редакция на диаграмите).

### Създаване на базите и зареждане на данни

1. Отворете **SSMS** и се свържете към SQL Server инстанцията си.
2. Отворете и изпълнете `GunsBG/sql/GunsBG_full_setup.sql` — създава релационната база `GunsBG` и необходимите обекти.
3. Изпълнете `GunsBG/sql/GunsBG_SeedData.sql` — добавя примерни данни.
4. Изпълнете `GunsBG/sql/GunsBG_DWH.sql` — създава Data Warehouse базата `GunsBG_DWH`.
5. Изпълнете `GunsBG/sql/GunsBG_ETL.sql` — дефинира ETL процеса.
6. За да стартирате зареждането на Data Warehouse, изпълнете:

```sql
USE GunsBG_DWH;
GO
EXEC dbo.usp_LoadGunsBG_DWH;
GO
```

Ако ETL скриптът вече изпълнява процедурата в края си, повторното ѝ изпълнение не е необходимо. При последващо зареждане е възможно да се актуализират дневните снимки на наличностите.

### Проверка на резултата

В SSMS изпълнете:

```sql
USE GunsBG_DWH;
GO
SELECT COUNT(*) AS SalesRows FROM dbo.FactSales;
SELECT COUNT(*) AS OrdersRows FROM dbo.FactOrders;
SELECT COUNT(*) AS InventoryRows FROM dbo.FactInventory;
```

### Отваряне на Power BI отчета

1. Отворете `GunsBG/powerbi/GunsBG_Report.pbix` с **Power BI Desktop**.
2. Ако е необходимо обновяване, от **Home → Transform data → Data source settings** променете SQL Server връзката към името на вашата инстанция.
3. Уверете се, че източникът е базата `GunsBG_DWH`.
4. Изберете **Home → Refresh**, за да обновите данните.

Отчетът **Sales Overview** включва три KPI показателя (`Total Revenue`, `Units Sold`, `Total Orders`), графики за статус на поръчките, месечни продажби, приходи по марки и десетте най-продавани продукта. Налични са филтри по месец, категория и марка.

## 6. Бележки

- Проектът е учебна реализация на **база данни, Data Warehouse, ETL и BI отчет**. 
- Данните в базата са примерни и са предназначени за демонстрация и анализ.
- При преместване на проекта на друг компютър може да е необходима промяна на връзката към SQL Server в Power BI.
