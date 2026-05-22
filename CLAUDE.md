# CLAUDE.md — Backend (Sales Management App)

## Project Overview
Hệ thống quản lý bán hàng gia đình — Backend layer.
Architecture: Hybrid Supabase — 3 lớp tùy complexity, dễ mở rộng từng phần.
DB: PostgreSQL (Supabase managed)
Deploy: Supabase (auto via CLI)

---

## ⚡ Quy tắc chọn layer — ĐỌC TRƯỚC KHI CODE

Mỗi tính năng mới phải chọn đúng layer. Sai layer = khó maintain, khó mở rộng.

```
Câu hỏi để chọn layer:

1. Chỉ là CRUD đơn giản, không có business logic?
   → Layer 1: Supabase Auto API (gọi thẳng từ FE)

2. Cần transaction, nhiều bảng phải nhất quán (tạo order + trừ kho)?
   → Layer 2: PostgreSQL DB Function (RPC)

3. Cần gọi bên ngoài (SMS, webhook, payment), xử lý file, logic phức tạp?
   → Layer 3: Edge Function (Deno TypeScript)
```

**KHÔNG được dùng Edge Function cho những gì DB Function làm được.**
**KHÔNG được dùng DB Function cho những gì Auto API làm được.**

---

## Layer 1 — Supabase Auto API
Gọi thẳng từ FE qua `@supabase/supabase-js`. Không cần viết code BE.

**Dùng cho:** list products, search, filter, get order detail, CRUD categories, upload ảnh...

```ts
// FE gọi trực tiếp — KHÔNG cần file BE nào
const { data } = await supabase
  .from('products')
  .select('*, category:categories(name)')
  .eq('is_active', true)
  .order('created_at', { ascending: false })
```

**Bảo vệ bằng RLS** — mọi table phải có policy (xem section RLS bên dưới).

---

## Layer 2 — PostgreSQL DB Functions (RPC)
Viết trong `supabase/migrations/`, gọi qua `supabase.rpc()` từ FE.

**Dùng cho:** create_order, cancel_order, adjust_stock, transfer_inventory — bất cứ thứ gì cần atomic transaction.

```sql
-- supabase/migrations/003_fn_create_order.sql
CREATE OR REPLACE FUNCTION create_order(
  p_customer_id uuid,
  p_items       jsonb,       -- [{ product_id, quantity, unit_price }]
  p_payment     text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER   -- chạy với quyền của user gọi (RLS vẫn apply)
AS $$
DECLARE
  v_order_id uuid;
  v_item     jsonb;
BEGIN
  -- 1. Tạo order
  INSERT INTO orders (customer_id, payment_method, total, created_by)
  VALUES (
    p_customer_id,
    p_payment,
    (SELECT SUM((item->>'unit_price')::numeric * (item->>'quantity')::int) FROM jsonb_array_elements(p_items) item),
    auth.uid()
  )
  RETURNING id INTO v_order_id;

  -- 2. Insert order_items + trừ stock (atomic)
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    INSERT INTO order_items (order_id, product_id, quantity, unit_price, subtotal)
    VALUES (
      v_order_id,
      (v_item->>'product_id')::uuid,
      (v_item->>'quantity')::int,
      (v_item->>'unit_price')::numeric,
      (v_item->>'unit_price')::numeric * (v_item->>'quantity')::int
    );

    -- Trừ stock, báo lỗi nếu không đủ hàng
    UPDATE products
    SET stock = stock - (v_item->>'quantity')::int
    WHERE id = (v_item->>'product_id')::uuid
      AND stock >= (v_item->>'quantity')::int;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Không đủ tồn kho cho sản phẩm %', v_item->>'product_id';
    END IF;

    -- Log inventory
    INSERT INTO inventory_logs (product_id, change_type, quantity, ref_order_id)
    VALUES ((v_item->>'product_id')::uuid, 'out', (v_item->>'quantity')::int, v_order_id);
  END LOOP;

  RETURN v_order_id;
EXCEPTION
  WHEN OTHERS THEN
    RAISE; -- rollback tự động, re-throw lỗi
END;
$$;
```

```ts
// FE gọi RPC — gọn như API call bình thường
const { data: orderId, error } = await supabase.rpc('create_order', {
  p_customer_id: customerId,
  p_items: items,
  p_payment: 'cash',
})
```

---

## Layer 3 — Edge Functions (Deno TypeScript)
Viết trong `supabase/functions/[name]/index.ts`.

**Dùng cho:** gửi Telegram/SMS notification, export PDF/Excel, tích hợp payment gateway, gọi 3rd party API, lấy Supabase usage stats.

```
supabase/functions/
├── _shared/
│   ├── cors.ts        # CORS headers dùng chung
│   ├── auth.ts        # verify JWT helper
│   └── response.ts    # { data, error } response helpers
├── notify-order/      # gửi Telegram khi có order mới
├── export-report/     # xuất báo cáo doanh thu PDF
├── get-usage/         # lấy Supabase free tier usage stats
└── process-payment/   # tích hợp payment (nếu cần sau này)
```

**Template chuẩn mỗi Edge Function:**
```ts
import { serve } from 'https://deno.land/std/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js'
import { corsHeaders } from '../_shared/cors.ts'
import { verifyAuth } from '../_shared/auth.ts'
import { ok, err } from '../_shared/response.ts'

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  const user = await verifyAuth(req)
  if (!user) return err(401, 'Unauthorized')

  const { someParam } = await req.json()
  // ... business logic

  return ok({ result: 'done' })
})
```

---

## Database Schema
- `profiles` — id (=auth.uid), full_name, role (owner|staff)
- `categories` — id, name, slug
- `products` — id, name, sku, price, cost, stock, category_id, image_url, is_active
- `customers` — id, name, phone, address, note
- `orders` — id, customer_id, total, payment_method, status, created_by, created_at
- `order_items` — id, order_id, product_id, quantity, unit_price, subtotal
- `inventory_logs` — id, product_id, change_type (in|out|adjust), quantity, note, ref_order_id

---

## RLS — Bắt buộc cho mọi table

```sql
-- Pattern chuẩn cho mọi table
ALTER TABLE products ENABLE ROW LEVEL SECURITY;

CREATE POLICY "authenticated can read" ON products
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "staff can insert/update" ON products
  FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid()))
  WITH CHECK (true);

CREATE POLICY "owner only delete" ON products
  FOR DELETE TO authenticated
  USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'owner'));
```

---

## Migrations
- Mỗi thay đổi schema = 1 file migration mới, **KHÔNG sửa file cũ**
- Đặt tên: `{number}_{verb}_{description}.sql`
  - `001_init_schema.sql`
  - `002_rls_policies.sql`
  - `003_fn_create_order.sql`
  - `004_add_discount_column.sql`
- Cuối mỗi file có `-- rollback:` comment ghi cách hoàn tác

---

## Commands
```bash
supabase start                    # local dev
supabase functions serve          # test Edge Functions local
supabase functions deploy [name]  # deploy function
supabase db push                  # apply migrations
supabase gen types typescript \
  --local > ../frontend/src/types/supabase.ts   # sync types sang FE
```

---

## DO NOT
- KHÔNG expose `SERVICE_ROLE_KEY` ra FE
- KHÔNG tắt RLS trên table chứa user data
- KHÔNG dùng Edge Function cho việc DB Function làm được (lãng phí invocation)
- KHÔNG sửa migration đã chạy trên production

## References (load khi cần)
- Schema chi tiết + ERD: @docs/database-schema.md
- RLS đã tạo: @docs/rls-policies.md
- Edge Function endpoints: @docs/api-endpoints.md
