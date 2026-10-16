-- Сгенерировано из products.csv: 5 строк, разделитель ','
CREATE TABLE IF NOT EXISTS "products" (
    "id" BIGINT,
    "name" VARCHAR(44),
    "category" VARCHAR(22),
    "price" DECIMAL(18,4),
    "in_stock" BOOLEAN,
    "added" DATE,
    "description" VARCHAR(38)
);

INSERT INTO "products" ("id", "name", "category", "price", "in_stock", "added", "description") VALUES
    (1, 'Ноутбук Lenovo', 'Электроника', 85999.90, TRUE, '2026-01-15', '15.6", 16 ГБ ОЗУ');
INSERT INTO "products" ("id", "name", "category", "price", "in_stock", "added", "description") VALUES
    (2, 'Мышь беспроводная', 'Электроника', 1299, TRUE, '2026-02-01', NULL);
INSERT INTO "products" ("id", "name", "category", "price", "in_stock", "added", "description") VALUES
    (3, 'Кружка «Программист»', 'Посуда', 450.5, FALSE, '2025-12-20', 'Подарок, керамика');
INSERT INTO "products" ("id", "name", "category", "price", "in_stock", "added", "description") VALUES
    (4, 'O''Reilly: Learning SQL', 'Книги', 3200, TRUE, '2026-03-10', 'Книга
на английском');
INSERT INTO "products" ("id", "name", "category", "price", "in_stock", "added", "description") VALUES
    (5, 'Коврик для мыши', 'Аксессуары', NULL, FALSE, '2026-03-11', 'Без цены');
