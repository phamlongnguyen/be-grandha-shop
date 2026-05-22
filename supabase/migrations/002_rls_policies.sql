-- 002_rls_policies.sql
-- Bật RLS + policy cho mọi bảng. Quy tắc chung:
--  - authenticated đọc được tất cả
--  - staff/owner insert/update được
--  - chỉ owner mới delete được

-- Helper: kiểm tra user hiện tại có phải owner không
create or replace function is_owner()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from profiles where id = auth.uid() and role = 'owner'
  );
$$;

-- Helper: kiểm tra user đã có profile (tức là staff hoặc owner)
create or replace function is_staff()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from profiles where id = auth.uid()
  );
$$;

-- =========================
-- profiles
-- =========================
alter table profiles enable row level security;

create policy "profiles: self or owner can read"
  on profiles for select to authenticated
  using (id = auth.uid() or is_owner());

create policy "profiles: owner can insert"
  on profiles for insert to authenticated
  with check (is_owner());

create policy "profiles: self update name, owner update all"
  on profiles for update to authenticated
  using (id = auth.uid() or is_owner())
  with check (id = auth.uid() or is_owner());

create policy "profiles: owner only delete"
  on profiles for delete to authenticated
  using (is_owner());

-- =========================
-- categories
-- =========================
alter table categories enable row level security;

create policy "categories: authenticated read"
  on categories for select to authenticated using (true);

create policy "categories: staff write"
  on categories for insert to authenticated
  with check (is_staff());

create policy "categories: staff update"
  on categories for update to authenticated
  using (is_staff()) with check (is_staff());

create policy "categories: owner delete"
  on categories for delete to authenticated
  using (is_owner());

-- =========================
-- products
-- =========================
alter table products enable row level security;

create policy "products: authenticated read"
  on products for select to authenticated using (true);

create policy "products: staff insert"
  on products for insert to authenticated
  with check (is_staff());

create policy "products: staff update"
  on products for update to authenticated
  using (is_staff()) with check (is_staff());

create policy "products: owner delete"
  on products for delete to authenticated
  using (is_owner());

-- =========================
-- customers
-- =========================
alter table customers enable row level security;

create policy "customers: authenticated read"
  on customers for select to authenticated using (true);

create policy "customers: staff insert"
  on customers for insert to authenticated
  with check (is_staff());

create policy "customers: staff update"
  on customers for update to authenticated
  using (is_staff()) with check (is_staff());

create policy "customers: owner delete"
  on customers for delete to authenticated
  using (is_owner());

-- =========================
-- orders
-- =========================
alter table orders enable row level security;

create policy "orders: authenticated read"
  on orders for select to authenticated using (true);

create policy "orders: staff insert"
  on orders for insert to authenticated
  with check (is_staff());

create policy "orders: staff update"
  on orders for update to authenticated
  using (is_staff()) with check (is_staff());

create policy "orders: owner delete"
  on orders for delete to authenticated
  using (is_owner());

-- =========================
-- order_items
-- =========================
alter table order_items enable row level security;

create policy "order_items: authenticated read"
  on order_items for select to authenticated using (true);

create policy "order_items: staff insert"
  on order_items for insert to authenticated
  with check (is_staff());

create policy "order_items: staff update"
  on order_items for update to authenticated
  using (is_staff()) with check (is_staff());

create policy "order_items: owner delete"
  on order_items for delete to authenticated
  using (is_owner());

-- =========================
-- inventory_logs
-- =========================
alter table inventory_logs enable row level security;

create policy "inventory_logs: authenticated read"
  on inventory_logs for select to authenticated using (true);

create policy "inventory_logs: staff insert"
  on inventory_logs for insert to authenticated
  with check (is_staff());

-- Inventory logs là audit trail → không cho update/delete (kể cả owner).
-- Nếu cần đảo log thì insert log mới ngược chiều.

-- rollback:
-- drop policy if exists "inventory_logs: staff insert" on inventory_logs;
-- drop policy if exists "inventory_logs: authenticated read" on inventory_logs;
-- alter table inventory_logs disable row level security;
-- (lặp lại cho từng bảng và drop is_owner(), is_staff())
