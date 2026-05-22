-- 010_fn_validate_promo.sql
-- RPC kiểm mã khuyến mãi: trả về { valid, discount, reason }.
-- Stateless — KHÔNG tăng times_used (create_order sẽ làm khi áp thật).
-- FE gọi để show preview discount trước khi user bấm "Thanh toán".

create or replace function validate_promo(
  p_code     text,
  p_subtotal numeric,
  p_items    jsonb default '[]'::jsonb  -- [{ product_id, quantity, category_id? }]
)
returns jsonb
language plpgsql
security invoker
stable
set search_path = public
as $$
declare
  v_promo     shop_promos%rowtype;
  v_scope_kind text;
  v_scope_id  uuid;
  v_match     boolean := false;
  v_discount  numeric(14,2) := 0;
begin
  -- 1) Tìm mã
  select * into v_promo from shop_promos where code = p_code and is_active = true;
  if v_promo.id is null then
    return jsonb_build_object('valid', false, 'reason', 'Mã khuyến mãi không tồn tại hoặc đã ngưng');
  end if;

  -- 2) Hết hạn?
  if v_promo.expires_at is not null and v_promo.expires_at < current_date then
    return jsonb_build_object('valid', false, 'reason', 'Mã đã hết hạn');
  end if;

  -- 3) Subtotal đủ?
  if p_subtotal < v_promo.min_order_amount then
    return jsonb_build_object(
      'valid', false,
      'reason', format('Đơn tối thiểu %s để dùng mã này', v_promo.min_order_amount::text)
    );
  end if;

  -- 4) Scope check
  if v_promo.scope = 'all' then
    v_match := true;
  else
    -- scope format: 'cat:<uuid>' hoặc 'sku:<uuid>'
    v_scope_kind := split_part(v_promo.scope, ':', 1);
    v_scope_id   := nullif(split_part(v_promo.scope, ':', 2), '')::uuid;

    if v_scope_kind = 'cat' and v_scope_id is not null then
      v_match := exists (
        select 1
        from jsonb_array_elements(p_items) i
        where (i->>'category_id')::uuid = v_scope_id
      );
    elsif v_scope_kind = 'sku' and v_scope_id is not null then
      v_match := exists (
        select 1
        from jsonb_array_elements(p_items) i
        where (i->>'product_id')::uuid = v_scope_id
      );
    end if;

    if not v_match then
      return jsonb_build_object(
        'valid', false,
        'reason', 'Mã không áp dụng cho các sản phẩm trong giỏ'
      );
    end if;
  end if;

  -- 5) Tính discount
  v_discount := case v_promo.type
    when 'percent' then round(p_subtotal * v_promo.value / 100, 0)
    when 'fixed'   then least(v_promo.value, p_subtotal)
    when 'bogo'    then 0   -- bogo logic phức tạp, xử lý ở create_order khi cần
  end;

  return jsonb_build_object(
    'valid',    true,
    'promo_id', v_promo.id,
    'code',     v_promo.code,
    'name',     v_promo.name,
    'type',     v_promo.type,
    'value',    v_promo.value,
    'discount', v_discount,
    'reason',   null
  );
end;
$$;

grant execute on function validate_promo(text, numeric, jsonb) to authenticated;

-- rollback:
-- drop function if exists validate_promo(text, numeric, jsonb);
