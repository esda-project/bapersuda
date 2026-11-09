-- ============================================================================
-- SIANGGARAN — 11 PERBAIKAN HAPUS DATA REALISASI (data hidup lagi setelah login ulang)
-- ----------------------------------------------------------------------------
-- Gejala  : Hapus di menu Input Realisasi tampak berhasil, tetapi setelah logout
--           lalu login lagi data yang dihapus muncul kembali.
-- Penyebab: Supabase TIDAK mengirim error bila DELETE ditolak oleh RLS/izin; ia
--           hanya menghapus 0 baris. Versi lama aplikasi tidak memeriksa jumlah
--           baris yang terhapus, sehingga data hanya hilang dari tampilan.
--           (index.html terbaru sudah memeriksanya dan akan menampilkan pesan
--            gagal bila server menolak.)
-- Script  : 1) menampilkan kondisi izin saat ini (BAGIAN A, hanya membaca)
--           2) memulihkan izin & kebijakan hapus yang benar (BAGIAN B)
--           3) memverifikasi hasilnya (BAGIAN C, hanya membaca)
-- Data    : TIDAK ada data anggaran/realisasi/kas yang diubah atau dihapus.
-- Aman diulang (idempotent). Jalankan di Supabase > SQL Editor > Run.
-- Aturan  : sama dengan 01_tambahan_aman.sql — hanya role admin & input yang
--           boleh menghapus; role input dibatasi ke nama PPTK-nya; kpa & view
--           tetap hanya-baca.
-- ============================================================================


-- ============================================================================
-- BAGIAN A — DIAGNOSA (hanya membaca; lihat hasil tiap tab di Results)
-- ============================================================================

-- A1. Apakah RLS aktif dan apa saja kebijakan di tabel realisasi?
select schemaname, tablename, policyname, permissive, roles, cmd
from pg_policies
where schemaname = 'public' and tablename in ('realisasi', 'anggaran')
order by tablename, cmd, policyname;

-- A2. Hak tabel untuk role authenticated (harus ada DELETE)
select table_name, grantee, privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
  and table_name in ('realisasi', 'anggaran')
  and grantee in ('authenticated', 'anon')
order by table_name, grantee, privilege_type;

-- A3. Daftar akun & role (cek akun yang dipakai menghapus berperan admin/input)
select username, nama, role, pptk_nama
from public.sianggaran_profiles
order by role, username;

-- A4. Trigger pada realisasi (harus hanya sg_audit_realisasi)
select trigger_name, event_manipulation, action_timing
from information_schema.triggers
where event_object_schema = 'public' and event_object_table = 'realisasi'
order by trigger_name;


-- ============================================================================
-- BAGIAN B — PERBAIKAN IZIN & KEBIJAKAN HAPUS
-- ============================================================================

-- B0. Fungsi bantu harus ada (dibuat oleh 01_tambahan_aman.sql)
do $$
begin
  if to_regprocedure('public.sg_auth_role()') is null
     or to_regprocedure('public.sg_auth_pptk()') is null
     or to_regprocedure('public.sg_norm_nama(text)') is null then
    raise exception 'Fungsi sg_auth_role/sg_auth_pptk/sg_norm_nama belum ada. Jalankan 01_tambahan_aman.sql terlebih dahulu.';
  end if;
end $$;

-- B1. RLS aktif + hak tabel (RLS yang membatasi baris)
alter table public.realisasi enable row level security;
alter table public.anggaran  enable row level security;

grant select, insert, update, delete on table public.realisasi to authenticated;
grant select, insert, update, delete on table public.anggaran  to authenticated;

-- B2. Kebijakan SELECT/DELETE realisasi (DELETE memakai aturan yang sama dengan 01)
drop policy if exists realisasi_sel_auth on public.realisasi;
create policy realisasi_sel_auth on public.realisasi for select to authenticated
  using (public.sg_auth_role() is not null
         and (public.sg_auth_pptk() is null or public.sg_norm_nama(pptk) = public.sg_auth_pptk()));

drop policy if exists realisasi_del_auth on public.realisasi;
create policy realisasi_del_auth on public.realisasi for delete to authenticated
  using (public.sg_auth_role() in ('admin','input')
         and (public.sg_auth_pptk() is null or public.sg_norm_nama(pptk) = public.sg_auth_pptk()));

-- B3. Kebijakan DELETE anggaran (alasan yang sama)
drop policy if exists anggaran_del_auth on public.anggaran;
create policy anggaran_del_auth on public.anggaran for delete to authenticated
  using (public.sg_auth_role() in ('admin','input')
         and (public.sg_auth_pptk() is null or public.sg_norm_nama(pptk) = public.sg_auth_pptk()));

-- B4. Kebijakan RESTRICTIVE sisa (bila ada) akan menolak semua hapus secara diam-diam.
--     Script ini TIDAK menghapusnya otomatis; bila A1 menampilkan permissive = 'RESTRICTIVE'
--     untuk cmd DELETE/ALL, kirimkan hasil A1 agar bisa dicek sebelum dihapus.


-- ============================================================================
-- BAGIAN C — VERIFIKASI (hanya membaca)
-- ============================================================================
select tablename, policyname, cmd, permissive
from pg_policies
where schemaname = 'public' and tablename in ('realisasi', 'anggaran') and cmd in ('DELETE', 'SELECT')
order by tablename, cmd;

select table_name, privilege_type
from information_schema.role_table_grants
where table_schema = 'public' and table_name in ('realisasi', 'anggaran')
  and grantee = 'authenticated' and privilege_type = 'DELETE';


-- ============================================================================
-- ROLLBACK (opsional): kembali ke kondisi 01_tambahan_aman.sql cukup dengan
-- menjalankan ulang 01_tambahan_aman.sql. Script ini tidak mengubah data.
-- ============================================================================
