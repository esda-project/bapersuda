-- ============================================================
-- SCRIPT 1 dari 4: DROP SEMUA VIEWS (urutan hilir ke hulu)
-- Jalankan ini PERTAMA, pastikan berhasil sebelum lanjut
-- ============================================================

-- Hilir dulu (bergantung pada view lain)
DROP VIEW IF EXISTS public.v_rekap_per_subkegiatan  CASCADE;
DROP VIEW IF EXISTS public.v_rekap_per_pptk         CASCADE;
DROP VIEW IF EXISTS public.v_rekap_per_sumber_dana  CASCADE;
DROP VIEW IF EXISTS public.v_lra                    CASCADE;
DROP VIEW IF EXISTS public.v_rekap_anggaran_realisasi CASCADE;

-- Tengah
DROP VIEW IF EXISTS public.v_realisasi_per_rekening CASCADE;

-- Hulu
DROP VIEW IF EXISTS public.v_pagu_aktif             CASCADE;

-- SIMARESDA (standalone)
DROP VIEW IF EXISTS public.v_statistik_surat_masuk  CASCADE;
DROP VIEW IF EXISTS public.v_statistik_surat_keluar CASCADE;
DROP VIEW IF EXISTS public.v_statistik_arsip        CASCADE;
DROP VIEW IF EXISTS public.v_peminjaman_aktif       CASCADE;
DROP VIEW IF EXISTS public.v_dashboard_summary      CASCADE;
DROP VIEW IF EXISTS public.v_pengguna_publik        CASCADE;

-- Verifikasi: hasilnya harus 0 baris
SELECT viewname FROM pg_views
WHERE schemaname = 'public'
  AND viewname LIKE 'v_%';
