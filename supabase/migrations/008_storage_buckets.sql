-- 008_storage_buckets.sql
-- FE requirement: storage-buckets.md
-- 4 buckets: product-images (public), staff-avatars (signed), store-assets (public), receipts (signed).
-- Storage policies áp dụng cho storage.objects, không cho storage.buckets.

-- =========================
-- Buckets
-- =========================
insert into storage.buckets (id, name, public) values
  ('product-images', 'product-images', true),
  ('staff-avatars',  'staff-avatars',  false),
  ('store-assets',   'store-assets',   true),
  ('receipts',       'receipts',       false)
on conflict (id) do nothing;

-- =========================
-- product-images: public read, authenticated write/delete
-- =========================
create policy "product-images: anyone select"
  on storage.objects for select to public
  using (bucket_id = 'product-images');

create policy "product-images: authenticated insert"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'product-images');

create policy "product-images: authenticated update"
  on storage.objects for update to authenticated
  using (bucket_id = 'product-images');

create policy "product-images: authenticated delete"
  on storage.objects for delete to authenticated
  using (bucket_id = 'product-images');

-- =========================
-- staff-avatars: self hoặc owner write, signed-URL only read
-- File path convention: <user_id>/avatar.<ext>
-- =========================
create policy "staff-avatars: authenticated select (via signed url too)"
  on storage.objects for select to authenticated
  using (bucket_id = 'staff-avatars');

create policy "staff-avatars: self or owner insert"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'staff-avatars'
    and (
      (storage.foldername(name))[1] = auth.uid()::text
      or is_owner()
    )
  );

create policy "staff-avatars: self or owner update"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'staff-avatars'
    and (
      (storage.foldername(name))[1] = auth.uid()::text
      or is_owner()
    )
  );

create policy "staff-avatars: owner delete"
  on storage.objects for delete to authenticated
  using (bucket_id = 'staff-avatars' and is_owner());

-- =========================
-- store-assets: public read, owner-only write/delete (logo, banner shop)
-- =========================
create policy "store-assets: anyone select"
  on storage.objects for select to public
  using (bucket_id = 'store-assets');

create policy "store-assets: owner insert"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'store-assets' and is_owner());

create policy "store-assets: owner update"
  on storage.objects for update to authenticated
  using (bucket_id = 'store-assets' and is_owner());

create policy "store-assets: owner delete"
  on storage.objects for delete to authenticated
  using (bucket_id = 'store-assets' and is_owner());

-- =========================
-- receipts: staff insert/select, owner delete
-- =========================
create policy "receipts: staff select"
  on storage.objects for select to authenticated
  using (bucket_id = 'receipts' and is_staff());

create policy "receipts: staff insert"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'receipts' and is_staff());

create policy "receipts: owner delete"
  on storage.objects for delete to authenticated
  using (bucket_id = 'receipts' and is_owner());

-- rollback:
-- delete from storage.buckets where id in ('product-images','staff-avatars','store-assets','receipts');
-- (Tự drop từng policy nếu cần — Supabase Studio dễ hơn)
