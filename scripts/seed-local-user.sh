#!/usr/bin/env bash
# Tạo owner mặc định trên local Supabase sau khi `supabase db reset`.
# Idempotent: chạy lại nhiều lần không lỗi.
#
# Cách dùng:
#   ./scripts/seed-local-user.sh                              # owner@local.test / owner123
#   ./scripts/seed-local-user.sh nv@local.test passw0rd staff # tạo staff với email/password custom
#
# Yêu cầu: supabase local đang chạy (`supabase start`).

set -euo pipefail

EMAIL="${1:-owner@local.test}"
PASSWORD="${2:-owner123}"
ROLE="${3:-owner}"
FULL_NAME="${4:-Chủ shop}"

# Lấy URL + service_role key từ supabase CLI
ENV_OUT=$(supabase status -o env 2>/dev/null) || {
  echo "❌ Không gọi được 'supabase status' — đã chạy 'supabase start' chưa?" >&2
  exit 1
}
API_URL=$(echo "$ENV_OUT" | awk -F'="' '/^API_URL=/{print $2}' | tr -d '"')
SR=$(echo "$ENV_OUT" | awk -F'="' '/^SERVICE_ROLE_KEY=/{print $2}' | tr -d '"')

if [ -z "$API_URL" ] || [ -z "$SR" ]; then
  echo "❌ Không parse được API_URL hoặc SERVICE_ROLE_KEY từ 'supabase status'" >&2
  exit 1
fi

echo "→ API: $API_URL"
echo "→ Email: $EMAIL  Role: $ROLE"

# 1) Tạo user (hoặc reuse nếu đã tồn tại)
RESP=$(curl -sS -X POST "$API_URL/auth/v1/admin/users" \
  -H "apikey: $SR" -H "Authorization: Bearer $SR" -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\",\"email_confirm\":true,\"user_metadata\":{\"full_name\":\"$FULL_NAME\"}}")

USER_ID=$(echo "$RESP" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('id',''))")

if [ -z "$USER_ID" ]; then
  # User có thể đã tồn tại — tìm theo email
  USER_ID=$(curl -sS "$API_URL/auth/v1/admin/users?email=$EMAIL" \
    -H "apikey: $SR" -H "Authorization: Bearer $SR" \
    | python3 -c "import sys,json;d=json.load(sys.stdin);u=(d.get('users') or [None])[0];print(u['id'] if u else '')")
fi

if [ -z "$USER_ID" ]; then
  echo "❌ Không tạo được user — response: $RESP" >&2
  exit 1
fi

echo "→ user_id: $USER_ID"

# 2) Upsert profile (Prefer: resolution=merge-duplicates để idempotent)
curl -sS -X POST "$API_URL/rest/v1/profiles" \
  -H "apikey: $SR" -H "Authorization: Bearer $SR" -H "Content-Type: application/json" \
  -H "Prefer: return=minimal,resolution=merge-duplicates" \
  -d "{\"id\":\"$USER_ID\",\"full_name\":\"$FULL_NAME\",\"role\":\"$ROLE\"}"

echo ""
echo "✅ Sẵn sàng đăng nhập:"
echo "   Email:    $EMAIL"
echo "   Password: $PASSWORD"
echo "   Role:     $ROLE"
