-- 020_search_indexes.sql
-- FE requirement: search-trigram-indexes.md
-- pg_trgm GIN cho ilike '%X%' search trên products (name, sku) + customers (name, phone).
-- Index size ~3x B-tree nhưng read-heavy nên acceptable.

create extension if not exists pg_trgm;

-- =========================
-- products
-- =========================
create index idx_products_name_trgm
  on products using gin (name gin_trgm_ops);

create index idx_products_sku_trgm
  on products using gin (sku gin_trgm_ops)
  where sku is not null;       -- partial: bỏ qua row null tiết kiệm index size

-- =========================
-- customers
-- =========================
create index idx_customers_name_trgm
  on customers using gin (name gin_trgm_ops);

create index idx_customers_phone_trgm
  on customers using gin (phone gin_trgm_ops)
  where phone is not null;

-- rollback:
-- drop index if exists idx_customers_phone_trgm;
-- drop index if exists idx_customers_name_trgm;
-- drop index if exists idx_products_sku_trgm;
-- drop index if exists idx_products_name_trgm;
-- (KHÔNG drop extension pg_trgm — có thể bảng khác đang dùng)
