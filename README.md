# be-grandha-shop

Backend Supabase cho app quản lý bán hàng gia đình.
Kiến trúc layer: xem [CLAUDE.md](./CLAUDE.md).

---

## 0. Cài đặt 1 lần

### macOS
```bash
brew install supabase/tap/supabase
# Docker Desktop bắt buộc (Supabase local chạy trong Docker)
brew install --cask docker
open -a Docker          # khởi động Docker rồi đợi 30s
```

### Kiểm tra
```bash
supabase --version      # >= 1.150
docker info             # phải chạy được, không báo lỗi connect
```

---

## 1. Chạy local (lần đầu)

```bash
cd be-grandha-shop
supabase start          # pull image lần đầu ~3-5 phút
```

Sau khi xong sẽ in ra:
```
API URL:        http://127.0.0.1:54321
Studio URL:     http://127.0.0.1:54323     ← UI quản lý DB
DB URL:         postgresql://postgres:postgres@127.0.0.1:54322/postgres
anon key:       eyJhbGciOi...               ← copy sang FE
service_role:   eyJhbGciOi...               ← TUYỆT ĐỐI không đẩy lên FE
```

→ Mở Studio: http://127.0.0.1:54323 để xem table, run SQL, xem auth users.

---

## 2. Apply migrations + seed

`supabase start` auto chạy mọi file trong `supabase/migrations/` theo thứ tự tên,
sau đó chạy `supabase/seed.sql` (chỉ local — file này KHÔNG được push lên remote).

Sau khi sửa migration / thêm migration mới:

```bash
supabase db reset       # drop DB local + chạy lại toàn bộ migration + seed
                        # ⚠️ Mất sạch data local, chỉ dùng khi dev
```

Hoặc apply migration mới mà KHÔNG reset:

```bash
supabase migration up
```

---

## 3. Tạo user owner đầu tiên (auth)

Sau `supabase start`, **chưa có user nào**. Tạo bằng Studio:

1. Mở http://127.0.0.1:54323 → **Authentication → Users → Add user**
2. Email: `owner@local.test`, password: `owner123`, tick **Auto Confirm User**
3. Copy `user_id` vừa tạo
4. Vào **SQL Editor**, chạy:
```sql
insert into profiles (id, full_name, role)
values ('<paste-user-id-here>', 'Chủ shop', 'owner');
```

Login từ FE bằng email/password đó là vào được với quyền owner.

---

## 4. Sync types sang FE

```bash
supabase gen types typescript --local \
  > ../fe-gandha-shop/src/types/supabase.ts
```

Chạy lại mỗi khi thay đổi schema. Có thể bỏ vào `package.json` script:
```json
{ "scripts": { "types:sync": "supabase gen types typescript --local > ../fe-gandha-shop/src/types/supabase.ts" } }
```

---

## 5. Test Edge Functions local (khi có)

```bash
supabase functions serve            # serve tất cả function trong supabase/functions/
supabase functions serve notify-order --no-verify-jwt   # debug 1 function
```

---

## 6. Deploy lên Supabase Cloud

### Lần đầu: link project
```bash
# 1. Tạo project tại https://supabase.com/dashboard
# 2. Lấy project ref (xxxxxxxxxxxxxxxxx) trong Settings → General
supabase login                              # mở browser auth
supabase link --project-ref <project-ref>
```

### Deploy migrations
```bash
supabase db push        # apply mọi migration chưa chạy lên remote
```

### Deploy Edge Functions
```bash
supabase functions deploy notify-order
supabase secrets set TELEGRAM_BOT_TOKEN=xxx STRIPE_KEY=xxx   # env cho function
```

---

## 7. CI/CD — auto deploy khi push lên `main`

Có sẵn workflow [.github/workflows/deploy-supabase.yml](./.github/workflows/deploy-supabase.yml).
Trigger khi push thay đổi vào `supabase/migrations/**`, `supabase/functions/**` hoặc `config.toml`.

Cần set 3 secrets trong GitHub repo (Settings → Secrets and variables → Actions):

| Secret | Lấy ở đâu |
|---|---|
| `SUPABASE_ACCESS_TOKEN` | https://supabase.com/dashboard/account/tokens → Generate new token |
| `SUPABASE_DB_PASSWORD` | Project Settings → Database → Connection string → password |
| `SUPABASE_PROJECT_ID`   | Project Settings → General → Reference ID (vd `abcdxyz123...`) |

Set nhanh bằng `gh` CLI:

```bash
gh secret set SUPABASE_ACCESS_TOKEN -b "sbp_xxx..."
gh secret set SUPABASE_DB_PASSWORD  -b "your-db-password"
gh secret set SUPABASE_PROJECT_ID   -b "abcdxyz123..."
```

Workflow sẽ:

1. `supabase link --project-ref <id>` — kết nối project
2. `supabase db push` — apply migration mới (idempotent, skip migration đã chạy)
3. `supabase functions deploy <name>` — deploy mọi edge function (bỏ qua `_shared/`)

**Lưu ý**: `seed.sql` KHÔNG được push lên remote, an toàn cho prod.

---

## 8. Workflow ngày thường

```bash
supabase start                              # bật local (Docker phải mở)
# ... code, sửa migration ...
supabase db reset                           # reset local nếu sửa migration cũ
supabase migration new add_discount_col     # tạo file migration mới
supabase db push                            # deploy lên remote khi xong
supabase stop                               # tắt local
```

---

## 8. RPC functions hiện có

| Function | Mô tả | Gọi từ FE |
|---|---|---|
| `create_order(p_customer_id, p_items, p_payment, p_note)` | Tạo đơn + trừ stock atomic | `supabase.rpc('create_order', { ... })` |
| `cancel_order(p_order_id, p_reason)` | Huỷ đơn + hoàn stock (chỉ owner khi đơn completed) | `supabase.rpc('cancel_order', { ... })` |
| `adjust_stock(p_product_id, p_change_type, p_quantity, p_note)` | Nhập/xuất/kiểm kê tồn | `supabase.rpc('adjust_stock', { ... })` |

Ví dụ FE gọi create_order:
```ts
const { data: orderId, error } = await supabase.rpc('create_order', {
  p_customer_id: '33333333-3333-3333-3333-333333333301',
  p_items: [
    { product_id: '22222222-2222-2222-2222-222222222201', quantity: 2 },
    { product_id: '22222222-2222-2222-2222-222222222204', quantity: 1 },
  ],
  p_payment: 'cash',
})
```

---

## Troubleshooting

| Lỗi | Fix |
|---|---|
| `Cannot connect to Docker` | Mở Docker Desktop, đợi icon cá voi xanh |
| `port 54321 already in use` | `supabase stop` → `supabase start` |
| `migration X already applied` sau khi sửa file cũ | `supabase db reset` (chỉ local!) |
| RPC báo `permission denied for function ...` | Thiếu `grant execute ... to authenticated` ở cuối migration |
| RLS chặn select khi đã login | Check user có trong `profiles` chưa (xem bước 3) |
