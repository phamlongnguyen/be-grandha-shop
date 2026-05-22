-- 018_store_config.sql
-- FE requirement: settings-store-devices.md §1
-- Single-row config: thông tin cửa hàng (tên, địa chỉ, STK, logo...).
-- Constraint id='singleton' đảm bảo chỉ tồn tại 1 row duy nhất.

create table store_config (
  id                  text primary key default 'singleton' check (id = 'singleton'),
  store_name          text not null default 'Gandha Shop',
  address             text,
  phone               text,
  bank_account        text,
  default_min_stock   int not null default 10 check (default_min_stock >= 0),
  logo_url            text,
  updated_at          timestamptz not null default now()
);

-- Seed row mặc định
insert into store_config (id) values ('singleton');

-- Trigger updated_at
create trigger trg_store_config_updated_at
  before update on store_config
  for each row execute function set_updated_at();

-- =========================
-- RLS — owner-only update
-- =========================
alter table store_config enable row level security;

create policy "store_config: authenticated read"
  on store_config for select to authenticated using (true);

create policy "store_config: owner update"
  on store_config for update to authenticated
  using (is_owner()) with check (is_owner());

-- KHÔNG cho INSERT/DELETE để giữ singleton — đã insert seed rồi.

-- rollback:
-- drop trigger if exists trg_store_config_updated_at on store_config;
-- drop table if exists store_config;
