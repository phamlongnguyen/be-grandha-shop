-- 004_fn_cancel_order.sql
-- RPC huỷ đơn: đổi status='cancelled', hoàn stock, ghi log 'in' (reversal).
-- Chỉ owner mới được huỷ đơn đã completed (tránh staff tự ý sửa doanh thu).
-- Gọi từ FE: supabase.rpc('cancel_order', { p_order_id, p_reason })

create or replace function cancel_order(
  p_order_id uuid,
  p_reason   text default null
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_status text;
  v_item   record;
begin
  -- Lock order row
  select status into v_status
    from orders
    where id = p_order_id
    for update;

  if v_status is null then
    raise exception 'Đơn hàng % không tồn tại', p_order_id;
  end if;

  if v_status = 'cancelled' then
    raise exception 'Đơn hàng đã bị huỷ trước đó';
  end if;

  -- Chỉ owner mới được huỷ đơn completed
  if v_status = 'completed' and not is_owner() then
    raise exception 'Chỉ owner mới được huỷ đơn đã hoàn tất';
  end if;

  -- Hoàn stock cho từng item + log reversal
  for v_item in
    select product_id, quantity from order_items where order_id = p_order_id
  loop
    update products
      set stock = stock + v_item.quantity
      where id = v_item.product_id;

    insert into inventory_logs (product_id, change_type, quantity, ref_order_id, created_by, note)
    values (v_item.product_id, 'in', v_item.quantity, p_order_id, auth.uid(),
            coalesce('cancel: ' || p_reason, 'cancel'));
  end loop;

  update orders
    set status = 'cancelled'
    where id = p_order_id;
end;
$$;

grant execute on function cancel_order(uuid, text) to authenticated;

-- rollback:
-- drop function if exists cancel_order(uuid, text);
