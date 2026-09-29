-- ============================================================
-- SIANGGARAN — Tambah kolom Metode Pemilihan Penyedia (Input Realisasi)
-- Jalankan SEKALI di Supabase SQL Editor. Aman dijalankan berulang.
-- Data lama tidak berubah (metode_pemilihan = NULL / tampil "-").
-- ============================================================
ALTER TABLE public.realisasi
  ADD COLUMN IF NOT EXISTS metode_pemilihan TEXT;

-- Batasi hanya 4 nilai yang valid (NULL tetap diperbolehkan)
ALTER TABLE public.realisasi DROP CONSTRAINT IF EXISTS realisasi_metode_pemilihan_check;
ALTER TABLE public.realisasi
  ADD CONSTRAINT realisasi_metode_pemilihan_check
  CHECK (metode_pemilihan IS NULL OR metode_pemilihan IN
    ('Pengadaan Langsung','e-Purchasing','Swakelola','Pengecualian'));

-- Refresh schema cache PostgREST agar kolom langsung dikenali API
NOTIFY pgrst, 'reload schema';
