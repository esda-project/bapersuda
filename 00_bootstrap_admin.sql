-- ============================================================================
-- SIANGGARAN — PEMULIHAN LOGIN (jalankan SETELAH 01_tambahan_aman.sql)
-- Tanpa langkah manual di Dashboard & tanpa Edge Function:
--  1. Membuat akun Supabase Auth untuk SETIAP baris tabel lama `pengguna`
--     (username + password LAMA tetap berlaku untuk login pertama).
--  2. Mengisi sianggaran_profiles; akun wajib ganti password saat login pertama.
--  3. Data anggaran/realisasi/kas/nota TIDAK disentuh. Aman diulang.
-- Domain email sintetis HARUS sama dengan AUTH_EMAIL_DOMAIN di index.html.
-- ============================================================================
create extension if not exists pgcrypto with schema extensions;

do $$
declare r record; uid uuid; em text; n_baru int := 0; n_profil int := 0;
  dom constant text := 'sianggaran.invalid';
begin
  for r in select lower(trim(username)) as username, nama, password, role, jabatan
           from public.pengguna where trim(coalesce(username,'')) <> '' loop
    continue when r.username !~ '^[a-z0-9._-]{3,40}$';
    em := r.username || '@' || dom;
    select id into uid from auth.users where email = em;
    if uid is null then
      uid := gen_random_uuid();
      insert into auth.users (instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
        raw_app_meta_data,raw_user_meta_data,created_at,updated_at,
        confirmation_token,recovery_token,email_change,email_change_token_new,email_change_token_current,phone_change,phone_change_token,reauthentication_token)
      values ('00000000-0000-0000-0000-000000000000',uid,'authenticated','authenticated',em,
        extensions.crypt(coalesce(nullif(r.password,''),encode(extensions.gen_random_bytes(9),'hex')), extensions.gen_salt('bf')),
        now(),'{"provider":"email","providers":["email"]}','{}',now(),now(),'','','','','','','','');
      insert into auth.identities (id,user_id,identity_data,provider,provider_id,last_sign_in_at,created_at,updated_at)
      values (gen_random_uuid(),uid,jsonb_build_object('sub',uid::text,'email',em,'email_verified',true),'email',uid::text,now(),now(),now());
      n_baru := n_baru + 1;
    end if;
    insert into public.sianggaran_profiles (id,username,nama,role,jabatan,must_change_password)
    values (uid,r.username,coalesce(nullif(r.nama,''),r.username),
            case when r.role in ('admin','kpa','input','view') then r.role else 'view' end,r.jabatan,true)
    on conflict (id) do nothing;
    if found then n_profil := n_profil + 1; end if;
  end loop;
  raise notice 'Akun Auth baru: %, profil baru: %', n_baru, n_profil;
end $$;

-- Harus menampilkan semua akun lama (minimal 1 admin):
select username, nama, role, must_change_password from public.sianggaran_profiles order by role, username;
