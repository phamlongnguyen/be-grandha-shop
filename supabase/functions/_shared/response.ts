// Response helpers — đảm bảo format thống nhất { data } hoặc { error }.

import { corsHeaders } from './cors.ts';

export function ok<T>(data: T, status = 200): Response {
  return new Response(JSON.stringify({ data }), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

export function err(status: number, message: string, details?: unknown): Response {
  return new Response(JSON.stringify({ error: { message, details } }), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
