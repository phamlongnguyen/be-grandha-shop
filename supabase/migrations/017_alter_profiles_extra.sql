-- 017_alter_profiles_extra.sql
-- FE requirement: settings-store-devices.md §2
-- Thêm 4 cột cho profiles: shift, color, avatar_url, is_online.

alter table profiles
  add column shift       text,                                -- 'Sáng' | 'Chiều' | 'Tối' | 'Cuối tuần'
  add column color       text check (color is null or color ~ '^#[0-9a-fA-F]{6}$'),
  add column avatar_url  text,
  add column is_online   boolean not null default false;

comment on column profiles.shift      is 'Ca trực: Sáng/Chiều/Tối/Cuối tuần';
comment on column profiles.color      is 'Chip color UI (hex #RRGGBB)';
comment on column profiles.avatar_url is 'URL avatar — link tới storage bucket staff-avatars';
comment on column profiles.is_online  is 'Trạng thái online (FE update khi heartbeat)';

-- rollback:
-- alter table profiles drop column is_online, drop column avatar_url, drop column color, drop column shift;
