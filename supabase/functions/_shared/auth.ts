// Auth helpers cho Edge Function.
// - verifyAuth: lấy user từ JWT trong header Authorization (Bearer ...)
// - requireOwner: assert user là owner (đọc từ profiles)
// Dùng anon-client cho verify (tự match RLS), service-role chỉ khi cần admin API.

import { createClient, SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';

export interface AuthedUser {
  id: string;
  email?: string;
}

export function getAnonClient(req: Request): SupabaseClient {
  return createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_ANON_KEY') ?? '',
    { global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } } },
  );
}

export function getServiceClient(): SupabaseClient {
  return createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    { auth: { persistSession: false } },
  );
}

export async function verifyAuth(req: Request): Promise<AuthedUser | null> {
  const client = getAnonClient(req);
  const { data, error } = await client.auth.getUser();
  if (error || !data.user) return null;
  return { id: data.user.id, email: data.user.email };
}

export async function requireOwner(req: Request): Promise<AuthedUser | null> {
  const user = await verifyAuth(req);
  if (!user) return null;

  const client = getAnonClient(req);
  const { data: profile } = await client
    .from('profiles')
    .select('role')
    .eq('id', user.id)
    .single();

  if (profile?.role !== 'owner') return null;
  return user;
}
