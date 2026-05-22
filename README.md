# be-grandha-shop

Backend Supabase cho app quản lý bán hàng gia đình.
Layer architecture (Auto API / RPC / Edge Function) xem [CLAUDE.md](./CLAUDE.md).

---

## Hiểu kiến trúc — 3 môi trường

```text
┌─────────────────────┐      ┌─────────────────────┐      ┌──────────────────────┐
│  Local (Docker)     │      │  GitHub (main)      │      │  Supabase Cloud      │
│  supabase start     │──▶──▶│  source of truth    │─CI──▶│  PRODUCTION          │
│  localhost:54321    │ push │  workflow trigger   │      │  FE thật kết nối     │
└─────────────────────┘      └─────────────────────┘      └──────────────────────┘
       ↑                                                              ↑
   nơi anh code + thử                                          KH thật + data thật
```

- **Local**: nơi thử nghiệm. Reset thoải mái, data mẫu nạp từ `supabase/seed.sql`.
- **GitHub** (`main`): **source of truth**. Code nào ở `main` = code sẽ chạy production.
- **Supabase Cloud**: production. **CHỈ** thay đổi qua CI/CD — không sửa schema bằng SQL editor trên dashboard.

**Quy tắc vàng**: mọi thay đổi DB đi qua migration file → commit → push → CI deploy.
Lý do: nếu sửa tay trên prod, local và prod sẽ lệch nhau, lần deploy sau sẽ vỡ.

---

## Daily flow — khi cần thay đổi schema DB

### Bước 1. Tạo migration mới

```bash
supabase migration new add_discount_to_orders
# → sinh file supabase/migrations/<timestamp>_add_discount_to_orders.sql
```

**Ý nghĩa**: mỗi thay đổi = 1 file mới. **KHÔNG sửa file cũ** vì file cũ đã chạy trên prod;
sửa file cũ = local replay được nhưng prod vẫn giữ trạng thái cũ → lệch.

### Bước 2. Viết SQL

```sql
alter table orders add column discount numeric(12,2) not null default 0;
-- rollback: alter table orders drop column discount;
```

Cuối mỗi file luôn ghi `-- rollback:` để biết cách hoàn tác khi cần.

### Bước 3. Test local trước khi push

```bash
supabase db reset
```

**Ý nghĩa**: drop DB local rồi replay TOÀN BỘ migration + `seed.sql` từ đầu.
Cách rẻ nhất để chắc rằng migration mới không phá migration cũ.
Nếu pass ở đây thì CI cũng sẽ pass.

### Bước 4. Sync types sang FE (nếu có thay đổi cột/bảng)

```bash
supabase gen types typescript --local > ../fe-gandha-shop/src/types/supabase.ts
```

**Ý nghĩa**: TypeScript ở FE thấy schema mới → autocomplete + compile báo lỗi nếu
FE truy cập cột không tồn tại. Đỡ phải chờ runtime mới biết sai.

### Bước 5. Commit + push

```bash
git add supabase/migrations/<file-mới>
git commit -m "feat(db): add discount column to orders"
git push
```

**Điều gì xảy ra (tự động)**: workflow [.github/workflows/deploy-supabase.yml](./.github/workflows/deploy-supabase.yml) chạy:

1. `supabase link` — kết nối project remote
2. `supabase db push` — apply migration mới lên prod (idempotent: skip cái đã chạy)
3. `supabase functions deploy` — deploy mọi edge function

→ Mở **Actions tab** trên GitHub xác nhận pass.

---

## Daily flow — khi cần thêm business logic

Trước khi viết code, chọn đúng layer ([CLAUDE.md](./CLAUDE.md) chi tiết):

| Tình huống | Layer | Ví dụ |
|---|---|---|
| CRUD đơn giản, không transaction | Auto API (FE gọi thẳng) | List sản phẩm, sửa profile |
| Cần atomic / nhiều bảng cùng nhất quán | **RPC** (Layer 2) | Tạo đơn + trừ stock |
| Gọi 3rd party, file, logic dài | **Edge Function** (Layer 3) | Gửi Telegram, export PDF |

### Viết RPC

1. `supabase migration new fn_<tên>` — tạo file SQL trong `supabase/migrations/`
2. Viết `create or replace function ...` trong file đó
3. **BẮT BUỘC** kết thúc bằng `grant execute on function ... to authenticated;`
   → thiếu là FE gọi sẽ bị `permission denied`
4. `supabase db reset` test local
5. Commit + push → CI tự deploy

### Viết Edge Function

1. `supabase functions new notify-order` — sinh `supabase/functions/notify-order/index.ts`
2. Viết code Deno, dùng helpers trong `_shared/` (cors, auth, response)
3. Test local: `supabase functions serve notify-order`
4. Nếu cần env vars trên prod: `supabase secrets set TELEGRAM_BOT_TOKEN=xxx`
5. Commit + push → CI tự deploy

---

## RPC functions hiện có

| Function | Mục đích | Khi nào FE gọi |
|---|---|---|
| `create_order(p_customer_id, p_items, p_payment, p_note)` | Tạo đơn + trừ stock + log inventory **atomic** | POS bấm "Thanh toán" |
| `cancel_order(p_order_id, p_reason)` | Huỷ đơn, hoàn stock (chỉ owner khi đơn `completed`) | Khách trả hàng / sai đơn |
| `adjust_stock(p_product_id, p_change_type, p_quantity, p_note)` | Nhập / xuất / kiểm kê tồn | Nhập hàng, kiểm kê |

**Tại sao dùng RPC chứ không dùng Auto API?** Vì những thao tác này phải chạy trong
1 transaction — nếu trừ stock xong mà insert order_item fail thì stock đã bị mất.
RPC chạy trong transaction PostgreSQL, fail thì rollback toàn bộ. FE gọi qua nhiều
API call rời rạc không đảm bảo được điều này.

Ví dụ FE gọi:

```ts
const { data: orderId, error } = await supabase.rpc('create_order', {
  p_customer_id: customerId,
  p_items: [
    { product_id: '...', quantity: 2 },
    { product_id: '...', quantity: 1 },
  ],
  p_payment: 'cash',
})
```

---

## Setup 1 lần (tham khảo)

<details>
<summary>Click để xem</summary>

### Cài tools (macOS)

```bash
brew install supabase/tap/supabase
brew install --cask docker
open -a Docker          # cần Docker chạy thì supabase mới start được
```

### Link project remote (cho local)

```bash
supabase login                                    # mở browser auth
supabase link --project-ref <project-ref>         # từ Settings → General
```

### GitHub Actions secrets

3 secrets bắt buộc cho workflow:

| Secret | Mục đích | Lấy ở đâu |
|---|---|---|
| `SUPABASE_ACCESS_TOKEN` | Auth CLI với Supabase API | https://supabase.com/dashboard/account/tokens |
| `SUPABASE_DB_PASSWORD` | Connect trực tiếp Postgres prod (để push migration) | Project Settings → Database |
| `SUPABASE_PROJECT_ID` | Project reference (vd `abcdxyz123...`) | Project Settings → General |

Set bằng `gh` CLI:

```bash
gh secret set SUPABASE_ACCESS_TOKEN -b "sbp_..."
gh secret set SUPABASE_DB_PASSWORD  -b "..."
gh secret set SUPABASE_PROJECT_ID   -b "..."
```

### Tạo user owner đầu tiên (local)

**Cách nhanh** — chạy script:

```bash
./scripts/seed-local-user.sh                                # owner@local.test / owner123
./scripts/seed-local-user.sh nv@local.test pass123 staff 'NV A'   # tạo staff custom
```

Script lấy service_role key tự động từ `supabase status`, tạo (hoặc reuse) auth user + upsert
`profiles`. Chạy lại nhiều lần không lỗi.

**Quy trình khuyên dùng**: mỗi lần `supabase db reset` xong → chạy script này để có owner login.

**Cách thủ công** (nếu không dùng script): mở http://127.0.0.1:54323
→ Authentication → Add user (`owner@local.test`, tick Auto Confirm)
→ SQL Editor: `insert into profiles (id, full_name, role) values ('<id>', 'Chủ shop', 'owner');`

</details>

---

## Commands cheatsheet

| Lệnh | Tác dụng |
|---|---|
| `supabase start` | Bật DB + API + Studio local (cần Docker) |
| `supabase stop` | Tắt — giải phóng Docker |
| `supabase status` | Xem URL + key của instance local |
| `supabase db reset` | Drop DB local + replay migration + seed |
| `supabase migration new <name>` | Tạo file migration trống |
| `supabase migration up` | Apply migration mới mà KHÔNG reset (giữ data local) |
| `supabase migration list` | So sánh migration local vs remote |
| `supabase gen types typescript --local` | Sinh types TS cho FE |
| `supabase functions serve [name]` | Chạy Edge Function local để debug |
| `supabase db push` | *(CI tự làm)* push migration lên remote |
| `supabase functions deploy [name]` | *(CI tự làm)* deploy edge function |

---

## Troubleshooting

| Lỗi | Nguyên nhân & Fix |
|---|---|
| `Cannot connect to Docker` | Docker Desktop chưa chạy → `open -a Docker`, đợi icon cá voi xanh |
| `port 54321 already in use` | Local Supabase đang chạy → `supabase stop` |
| `migration X already applied` sau khi sửa file cũ | KHÔNG sửa file cũ. Lỡ rồi → `supabase db reset` (chỉ local!) |
| `permission denied for function ...` từ FE | Thiếu `grant execute ... to authenticated;` cuối file RPC |
| RLS chặn `select` dù đã login | User chưa có row trong `profiles` → `is_staff()` / `is_owner()` trả false |
| CI fail `Remote migration versions not found` | Local thiếu migration mà remote đã chạy → `supabase migration repair --status reverted <num>` |
| CI fail `Unauthorized` khi link | `SUPABASE_ACCESS_TOKEN` sai/hết hạn → tạo token mới + `gh secret set` |
| `supabase db push` báo password sai | DB password đã đổi → cập nhật secret `SUPABASE_DB_PASSWORD` |
