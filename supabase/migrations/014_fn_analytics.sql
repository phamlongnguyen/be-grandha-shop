-- 014_fn_analytics.sql
-- FE requirement: analytics.md
-- 2 RPC cho Dashboard + Analytics: dashboard_today, top_products.

-- =========================
-- dashboard_today() — gom KPI cho dashboard 1 cú gọi
-- Trả về jsonb với revenue/profit/order_count hôm nay + % vs hôm qua + low_stock count.
-- =========================
create or replace function dashboard_today()
returns jsonb
language plpgsql
security invoker
stable
set search_path = public
as $$
declare
  v_today        date := current_date;
  v_yesterday    date := current_date - 1;
  v_today_rev    numeric(14,2) := 0;
  v_today_profit numeric(14,2) := 0;
  v_today_orders int := 0;
  v_yest_rev     numeric(14,2) := 0;
  v_yest_profit  numeric(14,2) := 0;
  v_low_stock    int := 0;
  v_rev_pct      numeric(5,1) := 0;
  v_profit_pct   numeric(5,1) := 0;
begin
  select coalesce(sum(total), 0),
         coalesce(sum(total - cost_total), 0),
         count(*)
    into v_today_rev, v_today_profit, v_today_orders
    from orders
    where status = 'completed' and date(created_at) = v_today;

  select coalesce(sum(total), 0),
         coalesce(sum(total - cost_total), 0)
    into v_yest_rev, v_yest_profit
    from orders
    where status = 'completed' and date(created_at) = v_yesterday;

  select count(*) into v_low_stock
    from products
    where is_active = true
      and not is_service
      and stock < min_stock;

  if v_yest_rev > 0 then
    v_rev_pct := round((v_today_rev - v_yest_rev) * 100 / v_yest_rev, 1);
  end if;
  if v_yest_profit > 0 then
    v_profit_pct := round((v_today_profit - v_yest_profit) * 100 / v_yest_profit, 1);
  end if;

  return jsonb_build_object(
    'revenue',         v_today_rev,
    'profit',          v_today_profit,
    'order_count',     v_today_orders,
    'low_stock_count', v_low_stock,
    'vs_yesterday_pct', jsonb_build_object(
      'revenue', v_rev_pct,
      'profit',  v_profit_pct
    )
  );
end;
$$;

grant execute on function dashboard_today() to authenticated;

-- =========================
-- top_products(p_from, p_to, p_sort, p_limit) — top-sellers theo profit/quantity/revenue
-- =========================
create or replace function top_products(
  p_from  date,
  p_to    date,
  p_sort  text default 'profit',
  p_limit int  default 10
)
returns table (
  id        uuid,
  name      text,
  sku       text,
  unit      text,
  qty_sold  int,
  revenue   numeric,
  profit    numeric
)
language plpgsql
security invoker
stable
set search_path = public
as $$
begin
  if p_sort not in ('profit', 'quantity', 'revenue') then
    raise exception 'p_sort phải là một trong: profit, quantity, revenue';
  end if;

  return query
    with agg as (
      select
        p.id                                                   as a_id,
        p.name                                                 as a_name,
        p.sku                                                  as a_sku,
        p.unit                                                 as a_unit,
        sum(oi.quantity)::int                                  as a_qty,
        sum(oi.subtotal)::numeric(14,2)                        as a_revenue,
        sum(oi.subtotal - oi.quantity * p.cost)::numeric(14,2) as a_profit
      from order_items oi
      join orders o on o.id = oi.order_id
      join products p on p.id = oi.product_id
      where o.status = 'completed'
        and date(o.created_at) between p_from and p_to
      group by p.id, p.name, p.sku, p.unit
    )
    select a_id, a_name, a_sku, a_unit, a_qty, a_revenue, a_profit
    from agg
    order by
      case when p_sort = 'profit'   then a_profit  end desc nulls last,
      case when p_sort = 'quantity' then a_qty     end desc nulls last,
      case when p_sort = 'revenue'  then a_revenue end desc nulls last
    limit p_limit;
end;
$$;

grant execute on function top_products(date, date, text, int) to authenticated;

-- rollback:
-- drop function if exists top_products(date, date, text, int);
-- drop function if exists dashboard_today();
