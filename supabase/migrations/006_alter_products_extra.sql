-- 006_alter_products_extra.sql
-- FE requirement: products-extra-columns.md
-- Thêm min_stock, is_service, unit + view tổng hợp sold trong 30 ngày.

alter table products
  add column min_stock  int     not null default 10 check (min_stock >= 0),
  add column is_service boolean not null default false,
  add column unit       text    not null default 'cái';

comment on column products.min_stock  is 'Mức tồn tối thiểu — trigger cảnh báo "sắp hết"';
comment on column products.is_service is 'Sản phẩm dịch vụ (photocopy, in ấn) — không trừ kho ngay cả khi stock=0';
comment on column products.unit       is 'Đơn vị bán: cái, cây, hộp, đôi, tờ, ream...';

-- View: tổng số lượng bán + doanh thu mỗi product trong 30 ngày gần nhất.
-- Dùng cho Dashboard "Top sản phẩm bán chạy" + Inventory "đã bán 30d".
create view v_products_sold_30d as
select
  oi.product_id,
  sum(oi.quantity)::int       as qty_sold_30d,
  sum(oi.subtotal)::numeric   as revenue_30d
from order_items oi
join orders o on o.id = oi.order_id
where o.status = 'completed'
  and o.created_at >= now() - interval '30 days'
group by oi.product_id;

-- View đọc qua RLS của bảng nguồn (orders, order_items) → authenticated read được luôn.
-- Không cần policy riêng cho view trong PostgreSQL.

grant select on v_products_sold_30d to authenticated;

-- rollback:
-- drop view if exists v_products_sold_30d;
-- alter table products drop column unit, drop column is_service, drop column min_stock;
