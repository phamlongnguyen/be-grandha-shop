-- 019_devices.sql
-- FE requirement: settings-store-devices.md §3
-- Đăng ký + tracking trạng thái thiết bị (máy in, scanner, két tiền).
-- Việc "kết nối" / "test" thực ra do FE giao tiếp WebUSB / Bluetooth — BE chỉ lưu state.

create table devices (
  id            uuid primary key default gen_random_uuid(),
  type          text not null check (type in (
                  'receipt_printer',   -- máy in hoá đơn
                  'label_printer',     -- máy in tem
                  'qr_scanner',        -- máy quét QR
                  'cash_drawer'        -- két tiền
                )),
  name          text not null,
  status        text not null default 'disconnected'
                  check (status in ('connected', 'disconnected', 'error')),
  last_test_at  timestamptz,
  meta          jsonb,
  created_at    timestamptz not null default now()
);

create index idx_devices_type on devices(type);

-- =========================
-- RLS
-- =========================
alter table devices enable row level security;

create policy "devices: authenticated read"
  on devices for select to authenticated using (true);

create policy "devices: staff insert"
  on devices for insert to authenticated with check (is_staff());

create policy "devices: staff update"
  on devices for update to authenticated
  using (is_staff()) with check (is_staff());

create policy "devices: owner delete"
  on devices for delete to authenticated using (is_owner());

-- rollback:
-- drop table if exists devices;
