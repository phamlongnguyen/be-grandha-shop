-- 009_promos_tables.sql
-- FE requirement: promos.md
-- 2 bảng: shop_promos (mã shop-wide), product_promos (giảm giá gắn vào từng product).

-- =========================
-- shop_promos — mã khuyến mãi áp dụng cho cả đơn
-- =========================
create table shop_promos (
  id                uuid primary key default gen_random_uuid(),
  code              text not null unique,
  name              text,
  type              text not null check (type in ('percent', 'fixed', 'bogo')),
  value             numeric(12,2) not null check (value > 0),
  scope             text not null default 'all',
    -- 'all' | 'cat:<uuid>' | 'sku:<uuid>'  — kiểm trong validate_promo
  min_order_amount  numeric(14,2) not null default 0 check (min_order_amount >= 0),
  times_used        int not null default 0 check (times_used >= 0),
  is_active         boolean not null default true,
  expires_at        date,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create index idx_shop_promos_code   on shop_promos(code) where is_active = true;
create index idx_shop_promos_active on shop_promos(is_active);

create trigger trg_shop_promos_updated_at
  before update on shop_promos
  for each row execute function set_updated_at();

-- =========================
-- product_promos — giảm giá gắn với product (vd "tựu trường -15%")
-- 1 product có tối đa 1 promo đang chạy
-- =========================
create table product_promos (
  product_id   uuid primary key references products(id) on delete cascade,
  type         text not null check (type in ('percent', 'fixed')),
  value        numeric(12,2) not null check (value > 0),
  label        text,
  expires_at   date,
  created_at   timestamptz not null default now()
);

-- =========================
-- RLS — shop_promos
-- =========================
alter table shop_promos enable row level security;

create policy "shop_promos: authenticated read"
  on shop_promos for select to authenticated using (true);

create policy "shop_promos: staff insert"
  on shop_promos for insert to authenticated with check (is_staff());

create policy "shop_promos: staff update"
  on shop_promos for update to authenticated
  using (is_staff()) with check (is_staff());

create policy "shop_promos: owner delete"
  on shop_promos for delete to authenticated using (is_owner());

-- =========================
-- RLS — product_promos
-- =========================
alter table product_promos enable row level security;

create policy "product_promos: authenticated read"
  on product_promos for select to authenticated using (true);

create policy "product_promos: staff insert"
  on product_promos for insert to authenticated with check (is_staff());

create policy "product_promos: staff update"
  on product_promos for update to authenticated
  using (is_staff()) with check (is_staff());

create policy "product_promos: owner delete"
  on product_promos for delete to authenticated using (is_owner());

-- rollback:
-- drop table if exists product_promos;
-- drop table if exists shop_promos;
