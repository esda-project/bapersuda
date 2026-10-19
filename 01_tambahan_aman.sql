-- ============================================================================
-- SIANGGARAN — TAHAP 5 / LANGKAH 1 dari 2: PENAMBAHAN AMAN (ADDITIVE)
-- ----------------------------------------------------------------------------
-- Sifat      : hanya MENAMBAH objek baru. Tidak menghapus kebijakan anon lama,
--              tidak mencabut hak apa pun, tidak mengubah/menghapus data.
--              Aplikasi LAMA tetap berjalan normal setelah script ini.
-- Aman diulang: ya (idempotent).
-- Prasyarat  : backup sudah dibuat (lihat RUNBOOK_TAHAP5.md, bagian 2).
-- Jalankan   : Supabase Dashboard > SQL Editor > paste seluruh file > Run.
-- Rollback   : 99_rollback.sql, BAGIAN B.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Tabel profil pengguna (terhubung ke Supabase Auth, TANPA kolom password)
-- ----------------------------------------------------------------------------
create table if not exists public.profiles (
  id                   uuid primary key references auth.users(id) on delete cascade,
  username             text not null unique,
  nama                 text not null,
  role                 text not null default 'view'
                         check (role in ('admin','kpa','input','view')),
  jabatan              text,
  nip                  text,
  jabatan_resmi        text,
  -- Bila terisi (hanya berlaku untuk role 'input'): akun hanya boleh melihat/
  -- menulis anggaran, realisasi, dan kas milik PPTK dengan nama tersebut.
  -- Bila NULL: akun operator melihat semua (perilaku lama akun non-"pptk*").
  pptk_nama            text,
  must_change_password boolean not null default true,
  created_at           timestamptz not null default now(),
  constraint profiles_username_format check (username ~ '^[a-z0-9._-]{3,40}$')
);

comment on table public.profiles is
  'Profil & peran pengguna SIANGGARAN. Ditulis HANYA oleh Edge Function admin-users (service_role).';

alter table public.profiles enable row level security;

-- ----------------------------------------------------------------------------
-- 2. Fungsi bantu (SECURITY DEFINER agar tidak rekursif terhadap RLS profiles)
-- ----------------------------------------------------------------------------
create or replace function public.norm_nama(t text)
returns text language sql immutable set search_path = ''
as $$ select upper(regexp_replace(btrim(coalesce(t,'')), '\s+', ' ', 'g')) $$;

create or replace function public.auth_role()
returns text language sql stable security definer set search_path = ''
as $$ select p.role from public.profiles p where p.id = (select auth.uid()) $$;

create or replace function public.auth_username()
returns text language sql stable security definer set search_path = ''
as $$ select p.username from public.profiles p where p.id = (select auth.uid()) $$;

-- NULL = tidak dibatasi; teks = dibatasi ke nama PPTK tsb (hanya role 'input').
create or replace function public.auth_pptk()
returns text language sql stable security definer set search_path = ''
as $$
  select case when p.role = 'input' and nullif(btrim(p.pptk_nama),'') is not null
              then public.norm_nama(p.pptk_nama) end
  from public.profiles p where p.id = (select auth.uid())
$$;

-- Satu-satunya hal yang boleh diubah pengguna atas profilnya sendiri.
create or replace function public.clear_must_change_password()
returns void language sql security definer set search_path = ''
as $$ update public.profiles set must_change_password = false where id = (select auth.uid()) $$;

revoke execute on function public.norm_nama(text)              from public, anon;
revoke execute on function public.auth_role()                  from public, anon;
revoke execute on function public.auth_username()              from public, anon;
revoke execute on function public.auth_pptk()                  from public, anon;
revoke execute on function public.clear_must_change_password() from public, anon;
grant  execute on function public.norm_nama(text)              to authenticated;
grant  execute on function public.auth_role()                  to authenticated;
grant  execute on function public.auth_username()              to authenticated;
grant  execute on function public.auth_pptk()                  to authenticated;
grant  execute on function public.clear_must_change_password() to authenticated;

-- ----------------------------------------------------------------------------
-- 3. Kebijakan profiles: semua pengguna login boleh MEMBACA direktori
--    (nama, role, NIP, jabatan — dipakai untuk penandatangan nota dinas).
--    Tidak ada kebijakan tulis => tidak ada yang bisa mengubah role lewat API.
-- ----------------------------------------------------------------------------
drop policy if exists profiles_select_auth on public.profiles;
create policy profiles_select_auth on public.profiles
  for select to authenticated using (true);

revoke all on table public.profiles from anon;
revoke insert, update, delete, truncate on table public.profiles from authenticated;
grant  select on table public.profiles to authenticated;

-- ----------------------------------------------------------------------------
-- 4. Kebijakan data anggaran / realisasi / kas / pengaturan (role authenticated)
--    Menambah kebijakan baru. Kebijakan anon lama BELUM dihapus (lihat 02).
-- ----------------------------------------------------------------------------
-- anggaran
drop policy if exists anggaran_sel_auth on public.anggaran;
drop policy if exists anggaran_ins_auth on public.anggaran;
drop policy if exists anggaran_upd_auth on public.anggaran;
drop policy if exists anggaran_del_auth on public.anggaran;
create policy anggaran_sel_auth on public.anggaran for select to authenticated
  using (public.auth_role() is not null
         and (public.auth_pptk() is null or public.norm_nama(pptk) = public.auth_pptk()));
create policy anggaran_ins_auth on public.anggaran for insert to authenticated
  with check (public.auth_role() in ('admin','input')
         and (public.auth_pptk() is null or public.norm_nama(pptk) = public.auth_pptk()));
create policy anggaran_upd_auth on public.anggaran for update to authenticated
  using (public.auth_role() in ('admin','input')
         and (public.auth_pptk() is null or public.norm_nama(pptk) = public.auth_pptk()))
  with check (public.auth_role() in ('admin','input')
         and (public.auth_pptk() is null or public.norm_nama(pptk) = public.auth_pptk()));
create policy anggaran_del_auth on public.anggaran for delete to authenticated
  using (public.auth_role() in ('admin','input')
         and (public.auth_pptk() is null or public.norm_nama(pptk) = public.auth_pptk()));

-- realisasi
drop policy if exists realisasi_sel_auth on public.realisasi;
drop policy if exists realisasi_ins_auth on public.realisasi;
drop policy if exists realisasi_upd_auth on public.realisasi;
drop policy if exists realisasi_del_auth on public.realisasi;
create policy realisasi_sel_auth on public.realisasi for select to authenticated
  using (public.auth_role() is not null
         and (public.auth_pptk() is null or public.norm_nama(pptk) = public.auth_pptk()));
create policy realisasi_ins_auth on public.realisasi for insert to authenticated
  with check (public.auth_role() in ('admin','input')
         and (public.auth_pptk() is null or public.norm_nama(pptk) = public.auth_pptk()));
create policy realisasi_upd_auth on public.realisasi for update to authenticated
  using (public.auth_role() in ('admin','input')
         and (public.auth_pptk() is null or public.norm_nama(pptk) = public.auth_pptk()))
  with check (public.auth_role() in ('admin','input')
         and (public.auth_pptk() is null or public.norm_nama(pptk) = public.auth_pptk()));
create policy realisasi_del_auth on public.realisasi for delete to authenticated
  using (public.auth_role() in ('admin','input')
         and (public.auth_pptk() is null or public.norm_nama(pptk) = public.auth_pptk()));

-- kas_anggaran: dibatasi lewat kepemilikan rekening di tabel anggaran
drop policy if exists kas_sel_auth on public.kas_anggaran;
drop policy if exists kas_ins_auth on public.kas_anggaran;
drop policy if exists kas_upd_auth on public.kas_anggaran;
drop policy if exists kas_del_auth on public.kas_anggaran;
create policy kas_sel_auth on public.kas_anggaran for select to authenticated
  using (public.auth_role() is not null
         and (public.auth_pptk() is null or exists (
               select 1 from public.anggaran a
               where a.kode_rekening = kas_anggaran.kode_rekening
                 and a.tahun = kas_anggaran.tahun
                 and public.norm_nama(a.pptk) = public.auth_pptk())));
create policy kas_ins_auth on public.kas_anggaran for insert to authenticated
  with check (public.auth_role() in ('admin','input')
         and (public.auth_pptk() is null or exists (
               select 1 from public.anggaran a
               where a.kode_rekening = kas_anggaran.kode_rekening
                 and a.tahun = kas_anggaran.tahun
                 and public.norm_nama(a.pptk) = public.auth_pptk())));
create policy kas_upd_auth on public.kas_anggaran for update to authenticated
  using (public.auth_role() in ('admin','input')
         and (public.auth_pptk() is null or exists (
               select 1 from public.anggaran a
               where a.kode_rekening = kas_anggaran.kode_rekening
                 and a.tahun = kas_anggaran.tahun
                 and public.norm_nama(a.pptk) = public.auth_pptk())))
  with check (public.auth_role() in ('admin','input')
         and (public.auth_pptk() is null or exists (
               select 1 from public.anggaran a
               where a.kode_rekening = kas_anggaran.kode_rekening
                 and a.tahun = kas_anggaran.tahun
                 and public.norm_nama(a.pptk) = public.auth_pptk())));
create policy kas_del_auth on public.kas_anggaran for delete to authenticated
  using (public.auth_role() in ('admin','input')
         and (public.auth_pptk() is null or exists (
               select 1 from public.anggaran a
               where a.kode_rekening = kas_anggaran.kode_rekening
                 and a.tahun = kas_anggaran.tahun
                 and public.norm_nama(a.pptk) = public.auth_pptk())));

-- app_settings: baca = semua pengguna login; tulis = admin
drop policy if exists settings_sel_auth on public.app_settings;
drop policy if exists settings_wr_auth  on public.app_settings;
create policy settings_sel_auth on public.app_settings for select to authenticated
  using (public.auth_role() is not null);
create policy settings_wr_auth on public.app_settings for all to authenticated
  using (public.auth_role() = 'admin') with check (public.auth_role() = 'admin');

-- ----------------------------------------------------------------------------
-- 5. Nota Dinas PPTK & PPK (kolom data jsonb berisi created_by = username)
--    PPTK : admin & kpa baca semua; operator hanya miliknya.
--    PPK  : admin & kpa baca semua; operator hanya miliknya.
--    Tulis: PPTK  -> admin bebas; operator hanya milik sendiri.
--           PPK   -> admin & kpa (peran PPK) bebas; operator hanya milik sendiri.
-- ----------------------------------------------------------------------------
do $$
begin
  if to_regclass('public.nota_dinas_pptk') is not null then
    execute 'drop policy if exists nd_pptk_sel_auth on public.nota_dinas_pptk';
    execute 'drop policy if exists nd_pptk_ins_auth on public.nota_dinas_pptk';
    execute 'drop policy if exists nd_pptk_upd_auth on public.nota_dinas_pptk';
    execute 'drop policy if exists nd_pptk_del_auth on public.nota_dinas_pptk';
    execute $p$create policy nd_pptk_sel_auth on public.nota_dinas_pptk for select to authenticated
      using (public.auth_role() in ('admin','kpa')
             or (public.auth_role() = 'input' and data->>'created_by' = public.auth_username()))$p$;
    execute $p$create policy nd_pptk_ins_auth on public.nota_dinas_pptk for insert to authenticated
      with check (public.auth_role() = 'admin'
             or (public.auth_role() = 'input' and data->>'created_by' = public.auth_username()))$p$;
    execute $p$create policy nd_pptk_upd_auth on public.nota_dinas_pptk for update to authenticated
      using (public.auth_role() = 'admin'
             or (public.auth_role() = 'input' and data->>'created_by' = public.auth_username()))
      with check (public.auth_role() = 'admin'
             or (public.auth_role() = 'input' and data->>'created_by' = public.auth_username()))$p$;
    execute $p$create policy nd_pptk_del_auth on public.nota_dinas_pptk for delete to authenticated
      using (public.auth_role() = 'admin'
             or (public.auth_role() = 'input' and data->>'created_by' = public.auth_username()))$p$;
  end if;

  if to_regclass('public.nota_dinas_ppk') is not null then
    execute 'drop policy if exists nd_ppk_sel_auth on public.nota_dinas_ppk';
    execute 'drop policy if exists nd_ppk_ins_auth on public.nota_dinas_ppk';
    execute 'drop policy if exists nd_ppk_upd_auth on public.nota_dinas_ppk';
    execute 'drop policy if exists nd_ppk_del_auth on public.nota_dinas_ppk';
    execute $p$create policy nd_ppk_sel_auth on public.nota_dinas_ppk for select to authenticated
      using (public.auth_role() in ('admin','kpa')
             or (public.auth_role() = 'input' and data->>'created_by' = public.auth_username()))$p$;
    execute $p$create policy nd_ppk_ins_auth on public.nota_dinas_ppk for insert to authenticated
      with check (public.auth_role() in ('admin','kpa')
             or (public.auth_role() = 'input' and data->>'created_by' = public.auth_username()))$p$;
    execute $p$create policy nd_ppk_upd_auth on public.nota_dinas_ppk for update to authenticated
      using (public.auth_role() in ('admin','kpa')
             or (public.auth_role() = 'input' and data->>'created_by' = public.auth_username()))
      with check (public.auth_role() in ('admin','kpa')
             or (public.auth_role() = 'input' and data->>'created_by' = public.auth_username()))$p$;
    execute $p$create policy nd_ppk_del_auth on public.nota_dinas_ppk for delete to authenticated
      using (public.auth_role() in ('admin','kpa')
             or (public.auth_role() = 'input' and data->>'created_by' = public.auth_username()))$p$;
  end if;
end $$;

-- ----------------------------------------------------------------------------
-- 6. Hak tabel untuk role authenticated (RLS yang membatasi baris)
-- ----------------------------------------------------------------------------
grant select, insert, update, delete on table
  public.anggaran, public.realisasi, public.kas_anggaran, public.app_settings
  to authenticated;
do $$
begin
  if to_regclass('public.nota_dinas_pptk') is not null then
    execute 'grant select, insert, update, delete on table public.nota_dinas_pptk to authenticated';
  end if;
  if to_regclass('public.nota_dinas_ppk') is not null then
    execute 'grant select, insert, update, delete on table public.nota_dinas_ppk to authenticated';
  end if;
end $$;

-- ----------------------------------------------------------------------------
-- 7. VERIFIKASI (hasil harus: profiles rls_aktif = true; daftar kebijakan *_auth ada)
-- ----------------------------------------------------------------------------
select tablename, rowsecurity as rls_aktif
from pg_tables where schemaname = 'public' order by tablename;

select tablename, policyname, roles, cmd
from pg_policies where schemaname = 'public' order by tablename, policyname;
