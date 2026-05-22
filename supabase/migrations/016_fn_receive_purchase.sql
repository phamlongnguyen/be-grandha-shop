-- 016_fn_receive_purchase.sql
-- FE requirement: purchases.md
-- RPC nhận hàng atomic: tăng stock, log inventory, optional update cost weighted-avg, đổi status='received'.

create or replace function receive_purchase(
  p_purchase_id  uuid,
  p_update_cost  boolean default false  -- true = cập nhật products.cost theo weighted average
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_purchase  purchases%rowtype;
  v_item      record;
  v_old_stock int;
  v_old_cost  numeric(12,2);
  v_new_cost  numeric(12,2);
begin
  -- Lock + load purchase
  select * into v_purchase
    from purchases
    where id = p_purchase_id
    for update;

  if v_purchase.id is null then
    raise exception 'Phiếu nhập % không tồn tại', p_purchase_id;
  end if;

  if v_purchase.status = 'received' then
    raise exception 'Phiếu nhập % đã được nhận trước đó', v_purchase.code;
  end if;

  if v_purchase.status = 'cancelled' then
    raise exception 'Phiếu nhập % đã bị huỷ', v_purchase.code;
  end if;

  -- Duyệt items: tăng stock, log, optional update cost
  for v_item in
    select product_id, quantity, unit_cost
      from purchase_items
      where purchase_id = p_purchase_id
  loop
    if p_update_cost then
      -- Weighted average: new_cost = (old_stock * old_cost + qty * unit_cost) / (old_stock + qty)
      select stock, cost into v_old_stock, v_old_cost
        from products
        where id = v_item.product_id
        for update;

      if (v_old_stock + v_item.quantity) > 0 then
        v_new_cost := round(
          (v_old_stock * v_old_cost + v_item.quantity * v_item.unit_cost)
          / (v_old_stock + v_item.quantity),
          2
        );
      else
        v_new_cost := v_item.unit_cost;
      end if;

      update products
        set stock = stock + v_item.quantity,
            cost  = v_new_cost
        where id = v_item.product_id;
    else
      update products
        set stock = stock + v_item.quantity
        where id = v_item.product_id;
    end if;

    insert into inventory_logs (product_id, change_type, quantity, created_by, note)
    values (v_item.product_id, 'in', v_item.quantity, auth.uid(),
            'Nhập từ PO ' || v_purchase.code);
  end loop;

  update purchases
    set status      = 'received',
        received_by = auth.uid(),
        received_at = now()
    where id = p_purchase_id;
end;
$$;

grant execute on function receive_purchase(uuid, boolean) to authenticated;

-- rollback:
-- drop function if exists receive_purchase(uuid, boolean);
