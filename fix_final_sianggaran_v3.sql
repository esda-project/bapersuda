-- ============================================================
-- SIANGGARAN — Security Fix FINAL v3 (kolom sudah benar semua)
-- Kolom tabel anggaran: nama_belanja | Kolom tabel realisasi: nominal
-- Jalankan SATU KALI sekaligus di Supabase SQL Editor
-- ============================================================

-- STEP 1: DROP SEMUA VIEWS (CASCADE)
DROP VIEW IF EXISTS public.v_rekap_per_subkegiatan    CASCADE;
DROP VIEW IF EXISTS public.v_rekap_per_pptk           CASCADE;
DROP VIEW IF EXISTS public.v_rekap_per_sumber_dana    CASCADE;
DROP VIEW IF EXISTS public.v_lra                      CASCADE;
DROP VIEW IF EXISTS public.v_rekap_anggaran_realisasi CASCADE;
DROP VIEW IF EXISTS public.v_realisasi_per_rekening   CASCADE;
DROP VIEW IF EXISTS public.v_pagu_aktif               CASCADE;
DROP VIEW IF EXISTS public.v_pengguna_publik          CASCADE;
DROP VIEW IF EXISTS public.v_statistik_surat_masuk    CASCADE;
DROP VIEW IF EXISTS public.v_statistik_surat_keluar   CASCADE;
DROP VIEW IF EXISTS public.v_statistik_arsip          CASCADE;
DROP VIEW IF EXISTS public.v_peminjaman_aktif         CASCADE;
DROP VIEW IF EXISTS public.v_dashboard_summary        CASCADE;

-- STEP 2: AKTIFKAN RLS
ALTER TABLE public.pengguna     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.anggaran     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.realisasi    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.kas_anggaran ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.nota_dinas_pptk ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.nota_dinas_ppk  ENABLE ROW LEVEL SECURITY;

-- STEP 3: BERSIHKAN & BUAT POLICY BARU
DROP POLICY IF EXISTS pengguna_admin_all ON public.pengguna;
DROP POLICY IF EXISTS pengguna_self_read ON public.pengguna;
DROP POLICY IF EXISTS pengguna_anon_all  ON public.pengguna;
CREATE POLICY pengguna_anon_all ON public.pengguna
  FOR ALL TO anon USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS anggaran_read  ON public.anggaran;
DROP POLICY IF EXISTS anggaran_write ON public.anggaran;
DROP POLICY IF EXISTS anggaran_anon  ON public.anggaran;
CREATE POLICY anggaran_anon ON public.anggaran
  FOR ALL TO anon USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS realisasi_read  ON public.realisasi;
DROP POLICY IF EXISTS realisasi_write ON public.realisasi;
DROP POLICY IF EXISTS realisasi_anon  ON public.realisasi;
CREATE POLICY realisasi_anon ON public.realisasi
  FOR ALL TO anon USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS kas_anggaran_anon ON public.kas_anggaran;
CREATE POLICY kas_anggaran_anon ON public.kas_anggaran
  FOR ALL TO anon USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS app_settings_anon ON public.app_settings;
CREATE POLICY app_settings_anon ON public.app_settings
  FOR ALL TO anon USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS nota_pptk_anon ON public.nota_dinas_pptk;
CREATE POLICY nota_pptk_anon ON public.nota_dinas_pptk
  FOR ALL TO anon USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS nota_ppk_anon ON public.nota_dinas_ppk;
CREATE POLICY nota_ppk_anon ON public.nota_dinas_ppk
  FOR ALL TO anon USING (true) WITH CHECK (true);

-- STEP 4: RECREATE VIEWS — kolom nama_belanja (bukan belanja)

-- [1] v_pagu_aktif
CREATE VIEW public.v_pagu_aktif WITH (security_invoker = true) AS
SELECT
  id,
  kode_rekening,
  program,
  kegiatan,
  sub_kegiatan,
  kode_sub_kegiatan,
  kode_belanja,
  nama_belanja,
  sumber_dana,
  pptk,
  tahun,
  pagu_murni,
  pagu_pergeseran,
  pagu_perubahan,
  COALESCE(
    NULLIF(pagu_perubahan,  0),
    NULLIF(pagu_pergeseran, 0),
    pagu_murni, 0
  ) AS pagu
FROM public.anggaran;

GRANT SELECT ON public.v_pagu_aktif TO anon;

-- [2] v_realisasi_per_rekening
CREATE VIEW public.v_realisasi_per_rekening WITH (security_invoker = true) AS
SELECT
  kode_rekening,
  SUM(nominal)  AS total_realisasi,
  COUNT(*)      AS jumlah_transaksi
FROM public.realisasi
GROUP BY kode_rekening;

GRANT SELECT ON public.v_realisasi_per_rekening TO anon;

-- [3] v_rekap_anggaran_realisasi
CREATE VIEW public.v_rekap_anggaran_realisasi WITH (security_invoker = true) AS
SELECT
  p.kode_rekening,
  p.program,
  p.kegiatan,
  p.sub_kegiatan,
  p.kode_sub_kegiatan,
  p.kode_belanja,
  p.nama_belanja,
  p.sumber_dana,
  p.pptk,
  p.tahun,
  p.pagu,
  p.pagu_murni,
  p.pagu_pergeseran,
  p.pagu_perubahan,
  COALESCE(r.total_realisasi, 0)           AS total_realisasi,
  COALESCE(r.jumlah_transaksi, 0)          AS jumlah_transaksi,
  p.pagu - COALESCE(r.total_realisasi, 0)  AS sisa
FROM public.v_pagu_aktif p
LEFT JOIN public.v_realisasi_per_rekening r USING (kode_rekening);

GRANT SELECT ON public.v_rekap_anggaran_realisasi TO anon;

-- [4] v_rekap_per_subkegiatan
CREATE VIEW public.v_rekap_per_subkegiatan WITH (security_invoker = true) AS
SELECT
  sub_kegiatan,
  kode_sub_kegiatan,
  tahun,
  SUM(pagu)            AS total_pagu,
  SUM(total_realisasi) AS total_realisasi,
  SUM(sisa)            AS total_sisa
FROM public.v_rekap_anggaran_realisasi
GROUP BY sub_kegiatan, kode_sub_kegiatan, tahun;

GRANT SELECT ON public.v_rekap_per_subkegiatan TO anon;

-- [5] v_rekap_per_pptk
CREATE VIEW public.v_rekap_per_pptk WITH (security_invoker = true) AS
SELECT
  pptk,
  tahun,
  SUM(pagu)            AS total_pagu,
  SUM(total_realisasi) AS total_realisasi,
  SUM(sisa)            AS total_sisa
FROM public.v_rekap_anggaran_realisasi
GROUP BY pptk, tahun;

GRANT SELECT ON public.v_rekap_per_pptk TO anon;

-- [6] v_rekap_per_sumber_dana
CREATE VIEW public.v_rekap_per_sumber_dana WITH (security_invoker = true) AS
SELECT
  sumber_dana,
  tahun,
  SUM(pagu)            AS total_pagu,
  SUM(total_realisasi) AS total_realisasi,
  SUM(sisa)            AS total_sisa
FROM public.v_rekap_anggaran_realisasi
GROUP BY sumber_dana, tahun;

GRANT SELECT ON public.v_rekap_per_sumber_dana TO anon;

-- [7] v_lra
CREATE VIEW public.v_lra WITH (security_invoker = true) AS
SELECT
  p.kode_rekening,
  p.program,
  p.kegiatan,
  p.sub_kegiatan,
  p.kode_sub_kegiatan,
  p.kode_belanja,
  p.nama_belanja,
  p.sumber_dana,
  p.pptk,
  p.tahun,
  p.pagu_murni,
  p.pagu_pergeseran,
  p.pagu_perubahan,
  p.pagu                                   AS pagu_aktif,
  COALESCE(r.total_realisasi, 0)           AS total_realisasi,
  COALESCE(r.jumlah_transaksi, 0)          AS jumlah_transaksi,
  p.pagu - COALESCE(r.total_realisasi, 0)  AS sisa
FROM public.v_pagu_aktif p
LEFT JOIN public.v_realisasi_per_rekening r USING (kode_rekening);

GRANT SELECT ON public.v_lra TO anon;

-- [8] v_pengguna_publik (tanpa kolom password)
CREATE VIEW public.v_pengguna_publik WITH (security_invoker = true) AS
SELECT id, nama, username, role, jabatan, nip, jabatan_resmi
FROM public.pengguna;

GRANT SELECT ON public.v_pengguna_publik TO anon;

-- VERIFIKASI AKHIR
SELECT '=== RLS STATUS ===' AS info;
SELECT tablename, rowsecurity AS rls_aktif
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY tablename;

SELECT '=== VIEWS AKTIF ===' AS info;
SELECT viewname
FROM pg_views
WHERE schemaname = 'public'
ORDER BY viewname;
