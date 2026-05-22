-- 001_init_schema.sql
-- Khởi tạo schema cho app quản lý bán hàng gia đình.
-- 7 bảng: profiles, categories, products, customers, orders, order_items, inventory_logs.

create extension if not exists "pgcrypto";

-- =========================
-- profiles
-- =========================
create table profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  full_name   text not null,
  role        text not null default 'staff' check (role in ('owner', 'staff')),
  created_at  timestamptz not null default now()
);

-- =========================
-- categories
-- =========================
create table categories (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  slug        text not null unique,
  created_at  timestamptz not null default now()
);

-- =========================
-- products
-- =========================
create table products (
  id           uuid primary key default gen_random_uuid(),
  name         text not null,
  sku          text unique,
  price        numeric(12,2) not null check (price >= 0),
  cost         numeric(12,2) not null default 0 check (cost >= 0),
  stock        int not null default 0 check (stock >= 0),
  category_id  uuid references categories(id) on delete set null,
  image_url    text,
  is_active    boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create index idx_products_category on products(category_id);
create index idx_products_active   on products(is_active);

-- =========================
-- customers
-- =========================
create table customers (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  phone       text,
  address     text,
  note        text,
  created_at  timestamptz not null default now()
);

create index idx_customers_phone on customers(phone);

-- =========================
-- orders
-- =========================
create table orders (
  id              uuid primary key default gen_random_uuid(),
  customer_id     uuid references customers(id) on delete set null,
  total           numeric(14,2) not null default 0 check (total >= 0),
  payment_method  text not null check (payment_method in ('cash', 'transfer', 'card', 'other')),
  status          text not null default 'completed' check (status in ('pending', 'completed', 'cancelled')),
  created_by      uuid references profiles(id) on delete set null,
  created_at      timestamptz not null default now()
);

create index idx_orders_customer on orders(customer_id);
create index idx_orders_created  on orders(created_at desc);
create index idx_orders_status   on orders(status);

-- =========================
-- order_items
-- =========================
create table order_items (
  id          uuid primary key default gen_random_uuid(),
  order_id    uuid not null references orders(id) on delete cascade,
  product_id  uuid not null references products(id) on delete restrict,
  quantity    int not null check (quantity > 0),
  unit_price  numeric(12,2) not null check (unit_price >= 0),
  subtotal    numeric(14,2) not null check (subtotal >= 0)
);

create index idx_order_items_order   on order_items(order_id);
create index idx_order_items_product on order_items(product_id);

-- =========================
-- inventory_logs
-- =========================
create table inventory_logs (
  id            uuid primary key default gen_random_uuid(),
  product_id    uuid not null references products(id) on delete cascade,
  change_type   text not null check (change_type in ('in', 'out', 'adjust')),
  quantity      int not null,
  note          text,
  ref_order_id  uuid references orders(id) on delete set null,
  created_by    uuid references profiles(id) on delete set null,
  created_at    timestamptz not null default now()
);

create index idx_inv_logs_product on inventory_logs(product_id);
create index idx_inv_logs_order   on inventory_logs(ref_order_id);

-- =========================
-- Trigger: tự động cập nhật updated_at cho products
-- =========================
create or replace function set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger trg_products_updated_at
  before update on products
  for each row execute function set_updated_at();

-- rollback:
-- drop trigger if exists trg_products_updated_at on products;
-- drop function if exists set_updated_at();
-- drop table if exists inventory_logs, order_items, orders, customers, products, categories, profiles cascade;
