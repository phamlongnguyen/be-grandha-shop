-- 012_fn_create_order_v3.sql
-- FE requirement: orders-extra-columns.md
-- create_order v3: thêm promo_code, discount_pct, received_amount + tính cost_total snapshot.
-- Logic giá: total = subtotal - promo_amount - discount_amount.

drop function if exists create_order(jsonb, uuid, text, text);

create or replace function create_order(
  p_items            jsonb,
  p_customer_id      uuid    default null,
  p_payment          text    default 'cash',
  p_note             text    default null,
  p_promo_code       text    default null,
  p_discount_pct     numeric default 0,
  p_received_amount  numeric default null
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_order_id uuid;
  v_item     jsonb;
  v_pid      uuid;
  v_qty      int;
  v_price    numeric(12,2);
  v_cost     numeric(12,2);
  v_is_svc   boolean;
  v_items_for_promo jsonb := '[]'::jsonb;

  v_subtotal       numeric(14,2) := 0;
  v_cost_total     numeric(14,2) := 0;
  v_promo_amount   numeric(14,2) := 0;
  v_discount_pct   numeric(5,2)  := coalesce(p_discount_pct, 0);
  v_discount_amount numeric(14,2) := 0;
  v_total          numeric(14,2);
  v_promo_result   jsonb;
  v_change         numeric(14,2);
begin
  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'Đơn hàng phải có ít nhất 1 sản phẩm';
  end if;

  if v_discount_pct < 0 or v_discount_pct > 50 then
    raise exception 'Discount tay phải trong khoảng 0-50%%';
  end if;

  -- Tạo order trống, các trường tiền tính sau
  insert into orders (customer_id, payment_method, total, created_by, promo_code, discount_pct)
  values (p_customer_id, p_payment, 0, auth.uid(), p_promo_code, v_discount_pct)
  returning id into v_order_id;

  -- Duyệt items: lock product, kiểm stock, insert order_item, log inventory, gom cost+subtotal
  for v_item in select * from jsonb_array_elements(p_items) loop
    v_pid := (v_item->>'product_id')::uuid;
    v_qty := (v_item->>'quantity')::int;

    if v_qty is null or v_qty <= 0 then
      raise exception 'Số lượng không hợp lệ cho sản phẩm %', v_pid;
    end if;

    select price, cost, is_service into v_price, v_cost, v_is_svc
      from products
      where id = v_pid and is_active = true
      for update;

    if v_price is null then
      raise exception 'Sản phẩm % không tồn tại hoặc đã ngưng bán', v_pid;
    end if;

    update products
      set stock = case when v_is_svc then stock else stock - v_qty end
      where id = v_pid
        and (v_is_svc or stock >= v_qty);

    if not found then
      raise exception 'Không đủ tồn kho cho sản phẩm %', v_pid;
    end if;

    insert into order_items (order_id, product_id, quantity, unit_price, subtotal)
    values (v_order_id, v_pid, v_qty, v_price, v_price * v_qty);

    if not v_is_svc then
      insert into inventory_logs (product_id, change_type, quantity, ref_order_id, created_by, note)
      values (v_pid, 'out', v_qty, v_order_id, auth.uid(), coalesce(p_note, 'sale'));
    end if;

    v_subtotal   := v_subtotal   + v_price * v_qty;
    v_cost_total := v_cost_total + v_cost  * v_qty;

    -- Gom item info cho validate_promo (scope check cần category_id)
    v_items_for_promo := v_items_for_promo || jsonb_build_object(
      'product_id', v_pid,
      'quantity',   v_qty,
      'category_id', (select category_id from products where id = v_pid)
    );
  end loop;

  -- Apply promo nếu có
  if p_promo_code is not null and length(trim(p_promo_code)) > 0 then
    v_promo_result := validate_promo(p_promo_code, v_subtotal, v_items_for_promo);
    if (v_promo_result->>'valid')::boolean is true then
      v_promo_amount := (v_promo_result->>'discount')::numeric;
      -- Tăng times_used
      update shop_promos set times_used = times_used + 1 where code = p_promo_code;
    else
      raise exception 'Mã khuyến mãi không hợp lệ: %', v_promo_result->>'reason';
    end if;
  end if;

  -- Discount tay tính trên subtotal sau khi đã trừ promo
  v_discount_amount := round((v_subtotal - v_promo_amount) * v_discount_pct / 100, 0);
  v_total := v_subtotal - v_promo_amount - v_discount_amount;

  if v_total < 0 then v_total := 0; end if;

  -- Tính tiền thối (chỉ cash)
  if p_payment = 'cash' and p_received_amount is not null then
    if p_received_amount < v_total then
      raise exception 'Tiền nhận (%) không đủ thanh toán (%)', p_received_amount, v_total;
    end if;
    v_change := p_received_amount - v_total;
  else
    v_change := null;
  end if;

  -- Cập nhật order
  update orders set
    subtotal         = v_subtotal,
    cost_total       = v_cost_total,
    promo_amount     = v_promo_amount,
    discount_amount  = v_discount_amount,
    total            = v_total,
    received_amount  = case when p_payment = 'cash' then p_received_amount else null end,
    change_amount    = v_change,
    status           = 'completed'
  where id = v_order_id;

  return v_order_id;
end;
$$;

grant execute on function create_order(jsonb, uuid, text, text, text, numeric, numeric) to authenticated;

-- rollback:
-- drop function if exists create_order(jsonb, uuid, text, text, text, numeric, numeric);
-- (Re-apply 007_fn_create_order_v2.sql để quay về v2)
