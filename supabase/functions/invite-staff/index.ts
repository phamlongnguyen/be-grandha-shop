// invite-staff — owner mời staff/owner mới qua email.
// Flow:
//   1. Verify caller là owner (JWT + profiles.role)
//   2. Dùng service_role tạo user trong auth (auto-confirm email)
//   3. Insert row vào profiles với role
//   4. Trả về { user_id, email }
//
// FE gọi: supabase.functions.invoke('invite-staff', { body: { email, full_name, role } })

import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
import { corsHeaders } from '../_shared/cors.ts';
import { requireOwner, getServiceClient } from '../_shared/auth.ts';
import { ok, err } from '../_shared/response.ts';

interface InviteBody {
  email: string;
  full_name: string;
  role?: 'staff' | 'owner';
  password?: string;     // optional — nếu null thì sinh tạm 12 ký tự
  shift?: string;
  color?: string;
}

function genTempPassword(len = 12): string {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789';
  let out = '';
  const arr = new Uint8Array(len);
  crypto.getRandomValues(arr);
  for (const n of arr) out += chars[n % chars.length];
  return out;
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST')   return err(405, 'Method not allowed');

  // 1) Caller phải là owner
  const caller = await requireOwner(req);
  if (!caller) return err(403, 'Chỉ owner mới được mời nhân viên');

  // 2) Parse body
  let body: InviteBody;
  try {
    body = await req.json();
  } catch {
    return err(400, 'Body JSON không hợp lệ');
  }

  const { email, full_name, role = 'staff', password, shift, color } = body;
  if (!email || !full_name) return err(400, 'Thiếu email hoặc full_name');
  if (role !== 'staff' && role !== 'owner') return err(400, 'role phải là staff hoặc owner');

  const finalPassword = password ?? genTempPassword();

  // 3) Tạo user trong auth bằng service_role
  const admin = getServiceClient();
  const { data: created, error: createErr } = await admin.auth.admin.createUser({
    email,
    password: finalPassword,
    email_confirm: true,
    user_metadata: { full_name },
  });
  if (createErr || !created.user) {
    return err(400, `Không tạo được user: ${createErr?.message ?? 'unknown'}`);
  }

  // 4) Insert profile
  const { error: profileErr } = await admin
    .from('profiles')
    .insert({
      id: created.user.id,
      full_name,
      role,
      shift: shift ?? null,
      color: color ?? null,
    });
  if (profileErr) {
    // Rollback: xoá user vừa tạo cho clean state
    await admin.auth.admin.deleteUser(created.user.id);
    return err(500, `Không tạo được profile: ${profileErr.message}`);
  }

  return ok({
    user_id: created.user.id,
    email,
    role,
    temp_password: password ? null : finalPassword,   // chỉ trả nếu BE tự sinh
  });
});
