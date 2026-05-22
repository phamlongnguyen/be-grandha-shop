-- 003_fn_create_order.sql
-- RPC tạo đơn hàng atomic: insert order + order_items + trừ stock + log inventory.
-- Gọi từ FE: supabase.rpc('create_order', { p_customer_id, p_items, p_payment, p_note })

create or replace function create_order(
  p_customer_id uuid,
  p_items       jsonb,        -- [{ product_id, quantity }]
  p_payment     text default 'cash',
  p_note        text default null
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

  -- 1) Tạo order trống (total tính sau)
  insert into orders (customer_id, payment_method, total, created_by)
  values (p_customer_id, p_payment, 0, auth.uid())
  returning id into v_order_id;

  -- 2) Duyệt từng item: lock row, kiểm stock, trừ stock, insert order_item + log
  for v_item in select * from jsonb_array_elements(p_items) loop
    v_pid := (v_item->>'product_id')::uuid;
    v_qty := (v_item->>'quantity')::int;

    if v_qty is null or v_qty <= 0 then
      raise exception 'Số lượng không hợp lệ cho sản phẩm %', v_pid;
    end if;

    -- Lock row để chống race condition khi nhiều client cùng bán
    select price into v_price
      from products
      where id = v_pid and is_active = true
      for update;

    if v_price is null then
      raise exception 'Sản phẩm % không tồn tại hoặc đã ngưng bán', v_pid;
    end if;

    -- Trừ stock có check
    update products
      set stock = stock - v_qty
      where id = v_pid and stock >= v_qty;

    if not found then
      raise exception 'Không đủ tồn kho cho sản phẩm %', v_pid;
    end if;

    insert into order_items (order_id, product_id, quantity, unit_price, subtotal)
    values (v_order_id, v_pid, v_qty, v_price, v_price * v_qty);

    insert into inventory_logs (product_id, change_type, quantity, ref_order_id, created_by, note)
    values (v_pid, 'out', v_qty, v_order_id, auth.uid(), coalesce(p_note, 'sale'));

    v_total := v_total + v_price * v_qty;
  end loop;

  -- 3) Cập nhật total
  update orders
    set total = v_total,
        status = 'completed'
    where id = v_order_id;

  return v_order_id;
end;
$$;

grant execute on function create_order(uuid, jsonb, text, text) to authenticated;

-- rollback:
-- drop function if exists create_order(uuid, jsonb, text, text);
