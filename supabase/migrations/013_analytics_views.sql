-- 013_analytics_views.sql
-- FE requirement: analytics.md
-- 2 view tổng hợp doanh thu / chi phí / lợi nhuận theo ngày + theo category.
-- Dùng cột snapshot orders.cost_total (từ migration 011) thay vì join order_items*products.cost
-- → profit ổn định với giá vốn đổi sau này.

-- =========================
-- v_analytics_daily: 1 row / ngày
-- =========================
create view v_analytics_daily as
select
  date(o.created_at)                                  as d,
  sum(o.subtotal)::numeric(14,2)                      as subtotal,
  sum(o.promo_amount + o.discount_amount)::numeric(14,2) as discount,
  sum(o.total)::numeric(14,2)                         as revenue,
  sum(o.cost_total)::numeric(14,2)                    as cost,
  sum(o.total - o.cost_total)::numeric(14,2)          as profit,
  count(o.id)::int                                    as order_count
from orders o
where o.status = 'completed'
group by date(o.created_at);

grant select on v_analytics_daily to authenticated;

-- =========================
-- v_analytics_by_category: 1 row / category / ngày
-- Cần per-line (order_items) để biết category — dùng products.cost (current) cho phần cost.
-- =========================
create view v_analytics_by_category as
select
  c.id                                                as category_id,
  c.name                                              as category_name,
  c.slug                                              as category_slug,
  date(o.created_at)                                  as d,
  sum(oi.subtotal)::numeric(14,2)                     as revenue,
  sum(oi.quantity * p.cost)::numeric(14,2)            as cost,
  sum(oi.subtotal - oi.quantity * p.cost)::numeric(14,2) as profit,
  sum(oi.quantity)::int                               as qty_sold
from orders o
join order_items oi on oi.order_id = o.id
join products  p  on p.id  = oi.product_id
join categories c on c.id  = p.category_id
where o.status = 'completed'
group by c.id, c.name, c.slug, date(o.created_at);

grant select on v_analytics_by_category to authenticated;

-- rollback:
-- drop view if exists v_analytics_by_category;
-- drop view if exists v_analytics_daily;
