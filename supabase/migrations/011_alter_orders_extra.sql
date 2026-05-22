-- 011_alter_orders_extra.sql
-- FE requirement: orders-extra-columns.md
-- Thêm các cột cho promo, discount tay, tiền nhận, tiền thối, cost snapshot.

alter table orders
  add column subtotal         numeric(14,2) not null default 0,    -- tổng trước discount
  add column promo_code        text,                                -- weak ref shop_promos.code
  add column promo_amount      numeric(14,2) not null default 0,    -- số tiền giảm từ mã
  add column discount_pct      numeric(5,2)  not null default 0
    check (discount_pct >= 0 and discount_pct <= 50),               -- discount tay 0–50%
  add column discount_amount   numeric(14,2) not null default 0,    -- = subtotal * discount_pct / 100
  add column cost_total        numeric(14,2) not null default 0,    -- snapshot cost tại thời điểm bán
  add column received_amount   numeric(14,2),                        -- chỉ cho payment=cash
  add column change_amount     numeric(14,2);                        -- = received - total

comment on column orders.subtotal       is 'Tổng tiền hàng trước mọi discount = sum(order_items.subtotal)';
comment on column orders.promo_code     is 'Mã khuyến mãi đã áp dụng (weak ref shop_promos.code)';
comment on column orders.promo_amount   is 'Số tiền giảm từ shop_promos';
comment on column orders.discount_pct   is 'Discount tay (0-50%), tính sau khi áp promo';
comment on column orders.discount_amount is 'Số tiền giảm từ discount_pct';
comment on column orders.cost_total     is 'Snapshot tổng cost tại thời điểm bán (= sum(qty * products.cost))';
comment on column orders.received_amount is 'Tiền khách đưa (chỉ cash). null nếu transfer/card';
comment on column orders.change_amount  is 'Tiền thối = received_amount - total. null nếu không cash';

-- Hỗ trợ analytics: profit = total - cost_total (tự compute on-the-fly).
create index idx_orders_promo_code on orders(promo_code) where promo_code is not null;

-- rollback:
-- alter table orders
--   drop column subtotal,
--   drop column promo_code,
--   drop column promo_amount,
--   drop column discount_pct,
--   drop column discount_amount,
--   drop column cost_total,
--   drop column received_amount,
--   drop column change_amount;
