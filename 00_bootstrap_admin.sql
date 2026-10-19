-- ============================================================================
-- SIANGGARAN — TAHAP 5 / LANGKAH 0: AKUN ADMIN PERTAMA
-- ----------------------------------------------------------------------------
-- Jalankan SETELAH 01_tambahan_aman.sql.
-- Prasyarat manual (di Dashboard Supabase):
--   Authentication > Users > Add user > Create new user
--     Email    : admin@sianggaran.invalid        (domain HARUS sama dengan AUTH_EMAIL_DOMAIN di klien & Edge Function)
--     Password : kata sandi kuat, minimal 12 karakter (jangan "admin123")
--     Centang  : Auto Confirm User
-- Lalu jalankan script ini. Aman diulang.
-- ============================================================================
insert into public.profiles (id, username, nama, role, jabatan, must_change_password)
select u.id, 'admin', 'Administrator', 'admin', 'Admin Sistem', false
from auth.users u
where u.email = 'admin@sianggaran.invalid'
on conflict (id) do update set role = 'admin', username = excluded.username;

-- Harus mengembalikan 1 baris dengan role = admin:
select id, username, nama, role from public.profiles where username = 'admin';
