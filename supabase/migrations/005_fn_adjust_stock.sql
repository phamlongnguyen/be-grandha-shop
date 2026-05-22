-- 005_fn_adjust_stock.sql
-- RPC điều chỉnh tồn kho atomic: cập nhật products.stock + ghi inventory_logs.
-- Dùng cho: nhập hàng ('in'), xuất bù ('out'), kiểm kê chênh lệch ('adjust').
-- Gọi từ FE: supabase.rpc('adjust_stock', { p_product_id, p_change_type, p_quantity, p_note })

create or replace function adjust_stock(
  p_product_id   uuid,
  p_change_type  text,         -- 'in' | 'out' | 'adjust'
  p_quantity     int,          -- in/out: số dương; adjust: signed (có thể âm)
  p_note         text default null
)
returns int                    -- trả về stock mới sau điều chỉnh
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_delta     int;
  v_new_stock int;
begin
  if p_change_type not in ('in', 'out', 'adjust') then
    raise exception 'change_type không hợp lệ: %', p_change_type;
  end if;

  if p_quantity is null or p_quantity = 0 then
    raise exception 'Số lượng phải khác 0';
  end if;

  -- Tính delta theo loại
  v_delta := case p_change_type
    when 'in'     then abs(p_quantity)
    when 'out'    then -abs(p_quantity)
    when 'adjust' then p_quantity          -- signed
  end;

  -- Lock row + cập nhật
  update products
    set stock = stock + v_delta
    where id = p_product_id
    returning stock into v_new_stock;

  if v_new_stock is null then
    raise exception 'Sản phẩm % không tồn tại', p_product_id;
  end if;

  if v_new_stock < 0 then
    raise exception 'Tồn kho không được âm (sản phẩm %, sau điều chỉnh: %)', p_product_id, v_new_stock;
  end if;

  insert into inventory_logs (product_id, change_type, quantity, created_by, note)
  values (p_product_id, p_change_type, v_delta, auth.uid(), p_note);

  return v_new_stock;
end;
$$;

grant execute on function adjust_stock(uuid, text, int, text) to authenticated;

-- rollback:
-- drop function if exists adjust_stock(uuid, text, int, text);
