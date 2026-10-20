-- ============================================================================
-- SIANGGARAN — TAHAP 5 / LANGKAH 2 dari 2: KUNCI AKSES ANON  (MENGUBAH HAK AKSES)
-- ----------------------------------------------------------------------------
-- JANGAN jalankan sebelum SEMUA syarat berikut terpenuhi:
--   [ ] 01_tambahan_aman.sql & 00_bootstrap_admin.sql sudah dijalankan
--   [ ] Edge Function admin-users sudah ter-deploy
--   [ ] index.html versi baru sudah ter-deploy ke Vercel
--   [ ] Semua akun sudah dibuat/diimpor dan SETIAP peran (admin, kpa, input, view)
--       berhasil login & melihat data yang benar (lihat RUNBOOK, bagian 5)
--   [ ] Backup database sudah dibuat dan dicek bisa dibuka
-- Dampak : aplikasi VERSI LAMA (login via tabel pengguna) berhenti berfungsi.
--          Tabel `pengguna` lama (berisi password teks biasa) tidak lagi
--          dapat dibaca oleh anon maupun authenticated.
-- Rollback: 99_rollback.sql, BAGIAN A.
-- ============================================================================
begin;

-- 1. Hapus SEMUA kebijakan yang berlaku untuk anon/public pada tabel aplikasi
do $$
declare r record;
begin
  for r in
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname = 'public'
      and tablename in ('pengguna','anggaran','realisasi','kas_anggaran','app_settings',
                        'nota_dinas_pptk','nota_dinas_ppk')
      and roles && array['anon','public']::name[]
  loop
    execute format('drop policy %I on %I.%I', r.policyname, r.schemaname, r.tablename);
    raise notice 'Kebijakan dihapus: %.%', r.tablename, r.policyname;
  end loop;
end $$;

-- 2. Cabut semua hak anon pada tabel aplikasi
revoke all on table public.pengguna, public.anggaran, public.realisasi,
                    public.kas_anggaran, public.app_settings, public.sianggaran_profiles
  from anon;
do $$
begin
  if to_regclass('public.nota_dinas_pptk') is not null then
    execute 'revoke all on table public.nota_dinas_pptk from anon';
  end if;
  if to_regclass('public.nota_dinas_ppk') is not null then
    execute 'revoke all on table public.nota_dinas_ppk from anon';
  end if;
end $$;

-- 3. Tabel pengguna lama: tutup total dari API (hanya service_role / Edge Function)
alter table public.pengguna enable row level security;
revoke all on table public.pengguna from anon, authenticated;

-- 4. View: ikuti RLS pemanggil, hanya untuk pengguna login
do $$
declare v text;
begin
  foreach v in array array['v_pagu_aktif','v_realisasi_per_rekening','v_rekap_anggaran_realisasi',
                           'v_rekap_per_subkegiatan','v_rekap_per_pptk','v_rekap_per_sumber_dana',
                           'v_lra']
  loop
    if to_regclass('public.'||v) is not null then
      execute format('alter view public.%I set (security_invoker = true)', v);
      execute format('revoke all on public.%I from anon', v);
      execute format('grant select on public.%I to authenticated', v);
    end if;
  end loop;
end $$;

-- CATATAN: view v_pengguna_publik sengaja TIDAK disentuh (di project ini dipakai aplikasi lain; kolom role bertipe app_role).

commit;

-- ----------------------------------------------------------------------------
-- VERIFIKASI (jalankan manual, semuanya harus lolos)
-- ----------------------------------------------------------------------------
-- (a) Tidak boleh ada kebijakan untuk anon/public (harus 0 baris):
select tablename, policyname, roles
from pg_policies
where schemaname = 'public' and roles && array['anon','public']::name[];

-- (b) Tidak boleh ada hak tabel untuk anon (harus 0 baris):
select table_name, privilege_type
from information_schema.role_table_grants
where table_schema = 'public' and grantee = 'anon';

-- (c) Uji sebagai anon: HARUS gagal dengan "permission denied for table ...".
--     (jalankan terpisah; rollback otomatis)
-- begin; set local role anon; select count(*) from public.anggaran; rollback;
-- begin; set local role anon; select count(*) from public.pengguna; rollback;
