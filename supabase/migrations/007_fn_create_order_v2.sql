-- 007_fn_create_order_v2.sql
-- FE requirement: create-order-customer-nullable.md
-- Cho phép p_customer_id nhận NULL (khách lẻ) — tránh phải tạo magic UUID.
-- Đồng thời reorder params để có thể đặt default cho p_customer_id
-- (PostgreSQL: param có default phải đứng sau param không có default).
-- FE dùng named args trong supabase.rpc() → reorder không ảnh hưởng call site.

-- PostgreSQL không cho thay đổi vị trí param bằng CREATE OR REPLACE → phải DROP trước.
drop function if exists create_order(uuid, jsonb, text, text);

create or replace function create_order(
  p_items        jsonb,                    -- required
  p_customer_id  uuid    default null,     -- nullable: khách lẻ
  p_payment      text    default 'cash',
  p_note         text    default null
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_order_id uuid;
  v_item     jsonb;
  v_total    numeric(14,2) := 0;
  v_price    numeric(12,2);
  v_qty      int;
  v_pid      uuid;
begin
  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'Đơn hàng phải có ít nhất 1 sản phẩm';
  end if;

  insert into orders (customer_id, payment_method, total, created_by)
  values (p_customer_id, p_payment, 0, auth.uid())
  returning id into v_order_id;

  for v_item in select * from jsonb_array_elements(p_items) loop
    v_pid := (v_item->>'product_id')::uuid;
    v_qty := (v_item->>'quantity')::int;

    if v_qty is null or v_qty <= 0 then
      raise exception 'Số lượng không hợp lệ cho sản phẩm %', v_pid;
    end if;

    select price into v_price
      from products
      where id = v_pid and is_active = true
      for update;

    if v_price is null then
      raise exception 'Sản phẩm % không tồn tại hoặc đã ngưng bán', v_pid;
    end if;

    -- Sản phẩm dịch vụ (is_service) không trừ stock, cho phép bán dù stock=0
    update products
      set stock = case when is_service then stock else stock - v_qty end
      where id = v_pid
        and (is_service or stock >= v_qty);

    if not found then
      raise exception 'Không đủ tồn kho cho sản phẩm %', v_pid;
    end if;

    insert into order_items (order_id, product_id, quantity, unit_price, subtotal)
    values (v_order_id, v_pid, v_qty, v_price, v_price * v_qty);

    -- Log inventory chỉ cho sản phẩm hàng hoá (không log cho service)
    insert into inventory_logs (product_id, change_type, quantity, ref_order_id, created_by, note)
    select v_pid, 'out', v_qty, v_order_id, auth.uid(), coalesce(p_note, 'sale')
    where not exists (select 1 from products where id = v_pid and is_service = true);

    v_total := v_total + v_price * v_qty;
  end loop;

  update orders
    set total = v_total,
        status = 'completed'
    where id = v_order_id;

  return v_order_id;
end;
$$;

grant execute on function create_order(jsonb, uuid, text, text) to authenticated;

-- rollback:
-- drop function if exists create_order(jsonb, uuid, text, text);
-- (Re-create v1 từ 003_fn_create_order.sql nếu cần)
