-- supabase/seed.sql
-- Seed data dev — Supabase tự chạy file này khi `supabase db reset` (local only).
-- KHÔNG được push lên remote bởi `supabase db push` → an toàn cho production.
-- Idempotent (chạy lại không bị trùng nhờ ON CONFLICT DO NOTHING).

-- Categories
insert into categories (id, name, slug) values
  ('11111111-1111-1111-1111-111111111101', 'Đồ uống',  'do-uong'),
  ('11111111-1111-1111-1111-111111111102', 'Bánh kẹo', 'banh-keo'),
  ('11111111-1111-1111-1111-111111111103', 'Gia dụng', 'gia-dung')
on conflict (id) do nothing;

-- Products
insert into products (id, name, sku, price, cost, stock, category_id, is_active) values
  ('22222222-2222-2222-2222-222222222201', 'Coca 330ml',       'COCA-330',  12000,  8500,  100, '11111111-1111-1111-1111-111111111101', true),
  ('22222222-2222-2222-2222-222222222202', 'Pepsi 330ml',      'PEPSI-330', 11000,  8000,   80, '11111111-1111-1111-1111-111111111101', true),
  ('22222222-2222-2222-2222-222222222203', 'Nước suối Lavie',  'LAVIE-500',  6000,  3500,  200, '11111111-1111-1111-1111-111111111101', true),
  ('22222222-2222-2222-2222-222222222204', 'Bánh Chocopie',    'CPIE-BOX',  45000, 32000,   50, '11111111-1111-1111-1111-111111111102', true),
  ('22222222-2222-2222-2222-222222222205', 'Kẹo Mentos',       'MENTOS-1',   8000,  5000,  120, '11111111-1111-1111-1111-111111111102', true),
  ('22222222-2222-2222-2222-222222222206', 'Khăn giấy Pulppy', 'PULP-10',   28000, 19000,   60, '11111111-1111-1111-1111-111111111103', true),
  ('22222222-2222-2222-2222-222222222207', 'Nước rửa chén Mỹ Hảo', 'MYHAO-800', 35000, 25000, 40, '11111111-1111-1111-1111-111111111103', true)
on conflict (id) do nothing;

-- Customers
insert into customers (id, name, phone, address) values
  ('33333333-3333-3333-3333-333333333301', 'Khách lẻ',         null,           null),
  ('33333333-3333-3333-3333-333333333302', 'Cô Lan tạp hoá',   '0901111111',   '12 Nguyễn Trãi'),
  ('33333333-3333-3333-3333-333333333303', 'Anh Tuấn quán cf', '0902222222',   '34 Lê Lợi')
on conflict (id) do nothing;

-- rollback:
-- delete from customers where id in (
--   '33333333-3333-3333-3333-333333333301','33333333-3333-3333-3333-333333333302','33333333-3333-3333-3333-333333333303');
-- delete from products where id like '22222222-%';
-- delete from categories where id like '11111111-%';
