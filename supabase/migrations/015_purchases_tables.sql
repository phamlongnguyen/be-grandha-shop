-- 015_purchases_tables.sql
-- FE requirement: purchases.md
-- Bảng quản lý nhập hàng: suppliers, purchases, purchase_items.
-- Code phiếu nhập 'NH-001', 'NH-002'... sinh tự động bằng sequence + trigger.

-- =========================
-- suppliers
-- =========================
create table suppliers (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  phone       text,
  address     text,
  note        text,
  created_at  timestamptz not null default now()
);

create index idx_suppliers_phone on suppliers(phone);

-- =========================
-- purchases
-- =========================
create sequence purchase_code_seq start 1;

create table purchases (
  id              uuid primary key default gen_random_uuid(),
  code            text unique not null,                -- 'NH-001'... auto sinh
  supplier_id     uuid references suppliers(id) on delete set null,
  invoice_number  text,
  total           numeric(14,2) not null default 0 check (total >= 0),
  payment_method  text not null check (payment_method in ('paid', 'debt_30d', 'installment')),
  status          text not null default 'pending'
    check (status in ('pending', 'received', 'cancelled')),
  note            text,
  created_by      uuid references profiles(id) on delete set null,
  received_by     uuid references profiles(id) on delete set null,
  received_at     timestamptz,
  created_at      timestamptz not null default now()
);

create index idx_purchases_supplier on purchases(supplier_id);
create index idx_purchases_status   on purchases(status);
create index idx_purchases_created  on purchases(created_at desc);

-- Trigger sinh code tự động khi insert (nếu FE không truyền)
create or replace function set_purchase_code()
returns trigger
language plpgsql
as $$
begin
  if new.code is null or new.code = '' then
    new.code := 'NH-' || lpad(nextval('purchase_code_seq')::text, 3, '0');
  end if;
  return new;
end;
$$;

create trigger trg_purchases_set_code
  before insert on purchases
  for each row execute function set_purchase_code();

-- =========================
-- purchase_items
-- =========================
create table purchase_items (
  id           uuid primary key default gen_random_uuid(),
  purchase_id  uuid not null references purchases(id) on delete cascade,
  product_id   uuid not null references products(id) on delete restrict,
  quantity     int not null check (quantity > 0),
  unit_cost    numeric(12,2) not null check (unit_cost >= 0),
  subtotal     numeric(14,2) not null check (subtotal >= 0)
);

create index idx_purchase_items_purchase on purchase_items(purchase_id);
create index idx_purchase_items_product  on purchase_items(product_id);

-- =========================
-- RLS — suppliers
-- =========================
alter table suppliers enable row level security;

create policy "suppliers: authenticated read"
  on suppliers for select to authenticated using (true);

create policy "suppliers: staff insert"
  on suppliers for insert to authenticated with check (is_staff());

create policy "suppliers: staff update"
  on suppliers for update to authenticated
  using (is_staff()) with check (is_staff());

create policy "suppliers: owner delete"
  on suppliers for delete to authenticated using (is_owner());

-- =========================
-- RLS — purchases
-- =========================
alter table purchases enable row level security;

create policy "purchases: authenticated read"
  on purchases for select to authenticated using (true);

create policy "purchases: staff insert"
  on purchases for insert to authenticated with check (is_staff());

create policy "purchases: staff update"
  on purchases for update to authenticated
  using (is_staff()) with check (is_staff());

create policy "purchases: owner delete"
  on purchases for delete to authenticated using (is_owner());

-- =========================
-- RLS — purchase_items
-- =========================
alter table purchase_items enable row level security;

create policy "purchase_items: authenticated read"
  on purchase_items for select to authenticated using (true);

create policy "purchase_items: staff insert"
  on purchase_items for insert to authenticated with check (is_staff());

create policy "purchase_items: staff update"
  on purchase_items for update to authenticated
  using (is_staff()) with check (is_staff());

create policy "purchase_items: owner delete"
  on purchase_items for delete to authenticated using (is_owner());

-- rollback:
-- drop table if exists purchase_items;
-- drop trigger if exists trg_purchases_set_code on purchases;
-- drop function if exists set_purchase_code();
-- drop table if exists purchases;
-- drop sequence if exists purchase_code_seq;
-- drop table if exists suppliers;
