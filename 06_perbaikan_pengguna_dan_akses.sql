-- ============================================================================
-- SIANGGARAN — 06 PERBAIKAN MENU PENGGUNA & HAK AKSES
-- ----------------------------------------------------------------------------
-- Masalah : Simpan di menu Pengguna (NIP, Batasi Data ke Nama PPTK, dsb) selalu
--           gagal karena bergantung penuh pada Edge Function `admin-users`
--           (harus di-deploy terpisah lewat CLI).
-- Solusi  : Pengelolaan akun dipindah ke fungsi database `sg_admin_users`
--           (SECURITY DEFINER, HANYA bisa dipakai akun ber-role admin).
--           Tidak perlu deploy Edge Function lagi.
-- Juga    : - Memastikan semua kolom profil ada (aman bila sudah ada).
--           - KPA/PPK menjadi VIEWER murni (tidak bisa menulis Nota Dinas PPK).
--           - Admin tidak bisa menurunkan/menghapus admin terakhir.
-- Data    : TIDAK ada data anggaran/realisasi/kas yang diubah atau dihapus.
-- Aman diulang (idempotent). Jalankan di Supabase > SQL Editor > Run.
-- Rollback: bagian paling bawah file ini.
-- ============================================================================

create extension if not exists pgcrypto with schema extensions;

-- 1. Pastikan kolom profil lengkap ------------------------------------------
alter table public.sianggaran_profiles add column if not exists jabatan              text;
alter table public.sianggaran_profiles add column if not exists nip                  text;
alter table public.sianggaran_profiles add column if not exists jabatan_resmi        text;
alter table public.sianggaran_profiles add column if not exists pptk_nama            text;
alter table public.sianggaran_profiles add column if not exists must_change_password boolean not null default true;

-- 2. Fungsi pengelola akun (admin saja) ---------------------------------------
create or replace function public.sg_admin_users(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_me        uuid := (select auth.uid());
  v_role      text;
  v_action    text := coalesce(payload->>'action','');
  v_id        uuid;
  v_target    text;
  v_username  text;
  v_nama      text;
  v_newrole   text;
  v_pass      text;
  v_email     text;
  v_uid       uuid;
  v_admins    int;
  r           record;
  j           jsonb;
  l_user      text;
  l_nama      text;
  l_role      text;
  v_report    jsonb := '[]'::jsonb;
  v_tmp       text;
  v_scoped    boolean;
  dom constant text := 'sianggaran.invalid';  -- HARUS sama dengan AUTH_EMAIL_DOMAIN di index.html
begin
  -- Otorisasi: ditentukan dari tabel profil di server, bukan dari klaim klien
  select p.role into v_role from public.sianggaran_profiles p where p.id = v_me;
  if v_me is null or v_role is distinct from 'admin' then
    raise exception 'Hanya admin yang boleh mengelola pengguna.' using errcode = '42501';
  end if;

  -- ------------------------------------------------------------------ update
  if v_action = 'update' then
    begin v_id := (payload->>'id')::uuid; exception when others then
      raise exception 'ID pengguna tidak valid.'; end;
    select p.role into v_target from public.sianggaran_profiles p where p.id = v_id;
    if v_target is null then raise exception 'Pengguna tidak ditemukan.'; end if;

    v_newrole := case when payload ? 'role' then btrim(coalesce(payload->>'role','')) else v_target end;
    if v_newrole not in ('admin','kpa','input','view') then raise exception 'Role tidak valid.'; end if;

    if v_target = 'admin' and v_newrole <> 'admin' then
      if v_id = v_me then raise exception 'Anda tidak dapat menurunkan role akun Anda sendiri.'; end if;
      select count(*) into v_admins from public.sianggaran_profiles where role = 'admin';
      if v_admins <= 1 then raise exception 'Harus tersisa minimal satu admin.'; end if;
    end if;

    if payload ? 'nama' and btrim(coalesce(payload->>'nama','')) = '' then
      raise exception 'Nama wajib diisi.';
    end if;

    update public.sianggaran_profiles p set
      nama          = case when payload ? 'nama'          then left(btrim(payload->>'nama'),200) else p.nama end,
      role          = v_newrole,
      jabatan       = case when payload ? 'jabatan'       then nullif(left(btrim(coalesce(payload->>'jabatan','')),200),'') else p.jabatan end,
      nip           = case when payload ? 'nip'           then nullif(left(btrim(coalesce(payload->>'nip','')),30),'') else p.nip end,
      jabatan_resmi = case when payload ? 'jabatan_resmi' then nullif(left(btrim(coalesce(payload->>'jabatan_resmi','')),200),'') else p.jabatan_resmi end,
      pptk_nama     = case when v_newrole <> 'input' then null
                           when payload ? 'pptk_nama'     then nullif(left(btrim(coalesce(payload->>'pptk_nama','')),200),'')
                           else p.pptk_nama end
    where p.id = v_id;

    v_pass := coalesce(payload->>'password','');
    if v_pass <> '' then
      if length(v_pass) < 12 then raise exception 'Password minimal 12 karakter.'; end if;
      update auth.users
         set encrypted_password = extensions.crypt(v_pass, extensions.gen_salt('bf')),
             updated_at = now()
       where id = v_id;
      if v_id <> v_me then
        update public.sianggaran_profiles set must_change_password = true where id = v_id;
      end if;
    end if;
    return jsonb_build_object('ok', true);
  end if;

  -- ------------------------------------------------------------------ create
  if v_action = 'create' then
    v_username := lower(btrim(coalesce(payload->>'username','')));
    v_nama     := left(btrim(coalesce(payload->>'nama','')),200);
    v_newrole  := btrim(coalesce(payload->>'role',''));
    v_pass     := coalesce(payload->>'password','');
    if v_username !~ '^[a-z0-9._-]{3,40}$' then raise exception 'Username 3–40 karakter: huruf kecil, angka, titik, strip, garis bawah.'; end if;
    if v_nama = '' then raise exception 'Nama wajib diisi.'; end if;
    if v_newrole not in ('admin','kpa','input','view') then raise exception 'Role tidak valid.'; end if;
    if length(v_pass) < 12 then raise exception 'Password minimal 12 karakter.'; end if;
    if exists (select 1 from public.sianggaran_profiles where username = v_username) then
      raise exception 'Username sudah digunakan.';
    end if;
    v_email := v_username || '@' || dom;
    if exists (select 1 from auth.users where email = v_email) then
      raise exception 'Akun Auth dengan username ini sudah ada.';
    end if;
    v_uid := gen_random_uuid();
    insert into auth.users (instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
      raw_app_meta_data,raw_user_meta_data,created_at,updated_at,
      confirmation_token,recovery_token,email_change,email_change_token_new,email_change_token_current,
      phone_change,phone_change_token,reauthentication_token)
    values ('00000000-0000-0000-0000-000000000000',v_uid,'authenticated','authenticated',v_email,
      extensions.crypt(v_pass, extensions.gen_salt('bf')),now(),
      '{"provider":"email","providers":["email"]}','{}',now(),now(),'','','','','','','','');
    insert into auth.identities (id,user_id,identity_data,provider,provider_id,last_sign_in_at,created_at,updated_at)
    values (gen_random_uuid(),v_uid,jsonb_build_object('sub',v_uid::text,'email',v_email,'email_verified',true),
            'email',v_uid::text,now(),now(),now());
    insert into public.sianggaran_profiles (id,username,nama,role,jabatan,nip,jabatan_resmi,pptk_nama,must_change_password)
    values (v_uid,v_username,v_nama,v_newrole,
      nullif(left(btrim(coalesce(payload->>'jabatan','')),200),''),
      nullif(left(btrim(coalesce(payload->>'nip','')),30),''),
      nullif(left(btrim(coalesce(payload->>'jabatan_resmi','')),200),''),
      case when v_newrole = 'input' then nullif(left(btrim(coalesce(payload->>'pptk_nama','')),200),'') end,
      true);
    return jsonb_build_object('ok', true, 'id', v_uid);
  end if;

  -- ------------------------------------------------------------------ delete
  if v_action = 'delete' then
    begin v_id := (payload->>'id')::uuid; exception when others then
      raise exception 'ID pengguna tidak valid.'; end;
    if v_id = v_me then raise exception 'Anda tidak dapat menghapus akun Anda sendiri.'; end if;
    select p.role into v_target from public.sianggaran_profiles p where p.id = v_id;
    if v_target is null then raise exception 'Pengguna tidak ditemukan.'; end if;
    if v_target = 'admin' then
      select count(*) into v_admins from public.sianggaran_profiles where role = 'admin';
      if v_admins <= 1 then raise exception 'Harus tersisa minimal satu admin.'; end if;
    end if;
    delete from auth.users where id = v_id;   -- profil ikut terhapus (ON DELETE CASCADE)
    return jsonb_build_object('ok', true);
  end if;

  -- ----------------------------------------------------------- import_legacy
  if v_action = 'import_legacy' then
    if to_regclass('public.pengguna') is null then
      raise exception 'Tabel pengguna lama tidak ditemukan.';
    end if;
    for r in execute 'select to_jsonb(t) as j from public.pengguna t'
    loop
      j := r.j;   -- kolom tabel lama dibaca lewat jsonb agar tidak error bila ada kolom yang tidak ada
      l_user := lower(btrim(coalesce(j->>'username','')));
      l_nama := btrim(coalesce(j->>'nama',''));
      l_role := coalesce(j->>'role','');
      if l_user !~ '^[a-z0-9._-]{3,40}$' or l_nama = '' then
        v_report := v_report || jsonb_build_object('username', l_user, 'status','DILEWATI: username/nama tidak valid');
        continue;
      end if;
      if exists (select 1 from public.sianggaran_profiles where username = l_user)
         or exists (select 1 from auth.users where email = l_user || '@' || dom) then
        v_report := v_report || jsonb_build_object('username', l_user, 'status','DILEWATI: sudah ada');
        continue;
      end if;
      v_tmp := substr(encode(extensions.gen_random_bytes(12),'hex'),1,14);
      v_uid := gen_random_uuid();
      v_email := l_user || '@' || dom;
      v_newrole := case when l_role in ('admin','kpa','input','view') then l_role else 'view' end;
      v_scoped := v_newrole = 'input' and l_user like 'pptk%';
      insert into auth.users (instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
        raw_app_meta_data,raw_user_meta_data,created_at,updated_at,
        confirmation_token,recovery_token,email_change,email_change_token_new,email_change_token_current,
        phone_change,phone_change_token,reauthentication_token)
      values ('00000000-0000-0000-0000-000000000000',v_uid,'authenticated','authenticated',v_email,
        extensions.crypt(v_tmp, extensions.gen_salt('bf')),now(),
        '{"provider":"email","providers":["email"]}','{}',now(),now(),'','','','','','','','');
      insert into auth.identities (id,user_id,identity_data,provider,provider_id,last_sign_in_at,created_at,updated_at)
      values (gen_random_uuid(),v_uid,jsonb_build_object('sub',v_uid::text,'email',v_email,'email_verified',true),
              'email',v_uid::text,now(),now(),now());
      insert into public.sianggaran_profiles (id,username,nama,role,jabatan,nip,jabatan_resmi,pptk_nama,must_change_password)
      values (v_uid,l_user,l_nama,v_newrole,j->>'jabatan',j->>'nip',j->>'jabatan_resmi',
              case when v_scoped then public.sg_norm_nama(l_nama) end, true);
      v_report := v_report || jsonb_build_object('username', l_user, 'nama', l_nama, 'role', v_newrole,
                                                 'temp_password', v_tmp, 'status','DIBUAT');
    end loop;
    return jsonb_build_object('ok', true, 'report', v_report);
  end if;

  raise exception 'Aksi tidak dikenal.';
end
$fn$;

revoke all on function public.sg_admin_users(jsonb) from public, anon;
grant execute on function public.sg_admin_users(jsonb) to authenticated;

-- Agar PostgREST langsung mengenali fungsi baru
notify pgrst, 'reload schema';

-- 3. KPA/PPK = VIEWER MURNI ----------------------------------------------------
--    Nota Dinas PPK: admin menulis; operator hanya miliknya; KPA hanya MEMBACA.
do $$
begin
  if to_regclass('public.nota_dinas_ppk') is not null then
    execute 'drop policy if exists nd_ppk_ins_auth on public.nota_dinas_ppk';
    execute 'drop policy if exists nd_ppk_upd_auth on public.nota_dinas_ppk';
    execute 'drop policy if exists nd_ppk_del_auth on public.nota_dinas_ppk';
    execute $p$create policy nd_ppk_ins_auth on public.nota_dinas_ppk for insert to authenticated
      with check (public.sg_auth_role() = 'admin'
             or (public.sg_auth_role() = 'input' and data->>'created_by' = public.sg_auth_username()))$p$;
    execute $p$create policy nd_ppk_upd_auth on public.nota_dinas_ppk for update to authenticated
      using (public.sg_auth_role() = 'admin'
             or (public.sg_auth_role() = 'input' and data->>'created_by' = public.sg_auth_username()))
      with check (public.sg_auth_role() = 'admin'
             or (public.sg_auth_role() = 'input' and data->>'created_by' = public.sg_auth_username()))$p$;
    execute $p$create policy nd_ppk_del_auth on public.nota_dinas_ppk for delete to authenticated
      using (public.sg_auth_role() = 'admin'
             or (public.sg_auth_role() = 'input' and data->>'created_by' = public.sg_auth_username()))$p$;
  end if;
end $$;

-- 4. Verifikasi (jalankan setelah script ini) ---------------------------------
select username, nama, role, nip, pptk_nama, must_change_password
from public.sianggaran_profiles order by role, username;

-- Daftar nama PPTK pada data anggaran (salin PERSIS ke kolom "Batasi Data ke Nama PPTK"):
select distinct pptk from public.anggaran where coalesce(pptk,'') <> '' order by 1;

-- ============================================================================
-- ROLLBACK (bila diperlukan):
--   drop function if exists public.sg_admin_users(jsonb);
--   -- lalu jalankan ulang bagian 5 dari 01_tambahan_aman.sql untuk mengembalikan
--   -- kebijakan nota_dinas_ppk lama (KPA boleh menulis Nota PPK).
-- ============================================================================
