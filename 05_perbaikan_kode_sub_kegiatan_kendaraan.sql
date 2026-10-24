-- ============================================================
-- SIANGGARAN — Perbaikan kode & nama Sub Kegiatan pemeliharaan kendaraan (v3)
-- Jalankan SEKALI di Supabase > SQL Editor (satu transaksi: gagal = batal total).
--
-- Rujukan: kode_rekening_pemeliharaan_Kendaraan.txt
--   4.01.01.2.06.0001  Penyediaan Jasa Pemeliharaan, Biaya Pemeliharaan, dan Pajak
--                      Kendaraan Perorangan Dinas atau Kendaraan Dinas Jabatan
--
-- Kode rekening di aplikasi = kode_sub_kegiatan || '.' || kode_belanja || '.' || sumber_dana.
-- Yang diubah HANYA kode/nama sub kegiatan, kegiatan, dan awalan kode_rekening.
-- Kolom pagu_murni / pagu_pergeseran / pagu_perubahan TIDAK disentuh.
-- Seluruh baris kas_anggaran (semua tahapan Murni/Pergeseran/Perubahan, semua bulan)
-- ikut dipindah ke kode_rekening baru bersama baris anggaran induknya.
--
-- Perubahan v3: anggaran kas yatim (tanpa anggaran induk) tidak dipindah, hanya dilaporkan.
-- Perubahan v2: baris dicocokkan lewat KOLOM kode_sub_kegiatan ATAU awalan
-- kode_rekening (data lama bisa tidak konsisten), dan foreign key
-- kas_anggaran_anggaran_fkey ditunda pengecekannya hanya selama transaksi ini.
-- ============================================================

BEGIN;

-- A. PEMETAAN ------------------------------------------------
CREATE TEMP TABLE _map (
  old_sk TEXT, new_sk TEXT,
  new_kode_kegiatan TEXT, new_kegiatan TEXT,
  new_sub_kegiatan TEXT
) ON COMMIT DROP;

INSERT INTO _map VALUES
('4.01.01.2.09.0001', '4.01.01.2.06.0001',
 '4.01.01.2.06', 'Administrasi Umum Perangkat Daerah',
 'Penyediaan Jasa Pemeliharaan, Biaya Pemeliharaan, dan Pajak Kendaraan Perorangan Dinas atau Kendaraan Dinas Jabatan');

-- Baris 2 lampiran (Operasional atau Lapangan) bertuliskan kode yang SAMA
-- (4.01.01.2.06.0001), sehingga TIDAK dijalankan secara bawaan.
-- Setelah kodenya pasti, hapus "--" dan isi:
--
-- INSERT INTO _map VALUES
-- ('4.01.01.2.09.0002', '<KODE_BARU>',
--  '<KODE_KEGIATAN_BARU>', '<NAMA_KEGIATAN_BARU>',
--  'Penyediaan Jasa Pemeliharaan, Biaya Pemeliharaan, Pajak dan Perizinan Kendaraan Dinas Operasional atau Lapangan');

-- B. CADANGAN (RLS aktif tanpa kebijakan = tertutup dari API) ---
CREATE TABLE IF NOT EXISTS public.bak_20261024_anggaran     AS SELECT * FROM public.anggaran;
CREATE TABLE IF NOT EXISTS public.bak_20261024_realisasi    AS SELECT * FROM public.realisasi;
CREATE TABLE IF NOT EXISTS public.bak_20261024_kas_anggaran AS SELECT * FROM public.kas_anggaran;
ALTER TABLE public.bak_20261024_anggaran     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bak_20261024_realisasi    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bak_20261024_kas_anggaran ENABLE ROW LEVEL SECURITY;

-- C. PENGAMAN TABRAKAN -----------------------------------------
DO $$
DECLARE n INT;
BEGIN
  SELECT count(*) INTO n
  FROM public.anggaran a
  JOIN _map m ON (a.kode_sub_kegiatan = m.old_sk
               OR left(a.kode_rekening, length(m.old_sk) + 1) = m.old_sk || '.')
  JOIN public.anggaran b
    ON b.tahun = a.tahun AND b.id <> a.id
   AND b.kode_rekening = m.new_sk || substr(a.kode_rekening, length(m.old_sk) + 1)
  WHERE left(a.kode_rekening, length(m.old_sk)) = m.old_sk;
  IF n > 0 THEN
    RAISE EXCEPTION 'DIBATALKAN: % baris anggaran bentrok dengan kode_rekening yang sudah ada. Tidak ada data yang diubah.', n;
  END IF;

  SELECT count(*) INTO n
  FROM public.kas_anggaran k
  JOIN _map m ON left(k.kode_rekening, length(m.old_sk) + 1) = m.old_sk || '.'
  JOIN public.kas_anggaran k2
    ON k2.tahun = k.tahun AND k2.tahapan = k.tahapan AND k2.bulan = k.bulan AND k2.id <> k.id
   AND k2.kode_rekening = m.new_sk || substr(k.kode_rekening, length(m.old_sk) + 1);
  IF n > 0 THEN
    RAISE EXCEPTION 'DIBATALKAN: % baris kas_anggaran bentrok. Tidak ada data yang diubah.', n;
  END IF;
END $$;

-- D. TUNDA PENGECEKAN FK SELAMA TRANSAKSI -------------------------
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'kas_anggaran_anggaran_fkey') THEN
    EXECUTE 'ALTER TABLE public.kas_anggaran ALTER CONSTRAINT kas_anggaran_anggaran_fkey DEFERRABLE INITIALLY DEFERRED';
  END IF;
END $$;

-- E. PERBAIKAN ----------------------------------------------------
-- E1. anggaran (kolom pagu tidak disentuh)
UPDATE public.anggaran a
SET kode_kegiatan     = m.new_kode_kegiatan,
    kegiatan          = m.new_kegiatan,
    kode_sub_kegiatan = m.new_sk,
    sub_kegiatan      = m.new_sub_kegiatan,
    kode_rekening     = CASE WHEN left(a.kode_rekening, length(m.old_sk)) = m.old_sk
                             THEN m.new_sk || substr(a.kode_rekening, length(m.old_sk) + 1)
                             ELSE a.kode_rekening END
FROM _map m
WHERE a.kode_sub_kegiatan = m.old_sk
   OR left(a.kode_rekening, length(m.old_sk) + 1) = m.old_sk || '.';

-- E2. realisasi
UPDATE public.realisasi x
SET kode_sub_kegiatan = m.new_sk,
    kode_rekening     = CASE WHEN left(x.kode_rekening, length(m.old_sk)) = m.old_sk
                             THEN m.new_sk || substr(x.kode_rekening, length(m.old_sk) + 1)
                             ELSE x.kode_rekening END
FROM _map m
WHERE x.kode_sub_kegiatan = m.old_sk
   OR left(x.kode_rekening, length(m.old_sk) + 1) = m.old_sk || '.';

-- E3. kas_anggaran: semua tahapan & bulan (termasuk yang soft-delete),
--     HANYA untuk rekening yang punya baris anggaran induk (setelah E1).
--     Baris kas "yatim" (tanpa anggaran induk) sudah ada sebelum migrasi ini
--     dan sengaja TIDAK diubah; daftarnya ditampilkan di akhir skrip.
UPDATE public.kas_anggaran k
SET kode_rekening = m.new_sk || substr(k.kode_rekening, length(m.old_sk) + 1)
FROM _map m
WHERE left(k.kode_rekening, length(m.old_sk) + 1) = m.old_sk || '.'
  AND EXISTS (
    SELECT 1 FROM public.anggaran a
    WHERE a.tahun = k.tahun
      AND a.kode_rekening = m.new_sk || substr(k.kode_rekening, length(m.old_sk) + 1));

-- F. PERIKSA FK SEKARANG, LALU KEMBALIKAN KE SEMULA ----------------
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'kas_anggaran_anggaran_fkey') THEN
    EXECUTE 'SET CONSTRAINTS kas_anggaran_anggaran_fkey IMMEDIATE';
    EXECUTE 'ALTER TABLE public.kas_anggaran ALTER CONSTRAINT kas_anggaran_anggaran_fkey NOT DEFERRABLE';
  END IF;
END $$;

-- G. VERIFIKASI -----------------------------------------------------
DO $$
DECLARE n INT;
BEGIN
  SELECT (SELECT count(*) FROM public.anggaran  a JOIN _map m ON a.kode_sub_kegiatan = m.old_sk
                                                  OR left(a.kode_rekening, length(m.old_sk)+1) = m.old_sk || '.')
       + (SELECT count(*) FROM public.realisasi x JOIN _map m ON x.kode_sub_kegiatan = m.old_sk
                                                  OR left(x.kode_rekening, length(m.old_sk)+1) = m.old_sk || '.')
  INTO n;
  IF n > 0 THEN
    RAISE EXCEPTION 'DIBATALKAN: masih ada % baris anggaran/realisasi berkode lama.', n;
  END IF;
END $$;

COMMIT;

-- ---- HASIL (jalankan terpisah bila perlu) ------------------------
-- 1) Baris yang berubah:
SELECT a.tahun, a.kode_sub_kegiatan, a.sub_kegiatan, a.kode_belanja, a.nama_belanja,
       a.sumber_dana, a.kode_rekening, a.pagu_murni, a.pagu_pergeseran, a.pagu_perubahan,
       (SELECT count(*) FROM public.kas_anggaran k
         WHERE k.tahun = a.tahun AND k.kode_rekening = a.kode_rekening) AS baris_kas
FROM public.anggaran a
WHERE a.kode_sub_kegiatan = '4.01.01.2.06.0001'
ORDER BY a.tahun, a.kode_rekening;

-- 2) Baris yang dulu TIDAK konsisten (kolom sub kegiatan berbeda dari awalan kode_rekening)
--    dan ikut dipindah. Periksa bahwa semuanya memang termasuk sub kegiatan ini:
SELECT b.tahun, b.kode_sub_kegiatan AS kolom_lama, left(b.kode_rekening, 17) AS awalan_rekening_lama,
       b.kode_belanja, b.nama_belanja, b.kode_rekening AS rekening_lama
FROM public.bak_20261024_anggaran b
WHERE left(b.kode_rekening, 17) = '4.01.01.2.09.0001'
  AND b.kode_sub_kegiatan IS DISTINCT FROM '4.01.01.2.09.0001';

-- 3) Anggaran kas YATIM berkode lama (tidak punya baris anggaran induk; sudah begitu
--    sebelum migrasi, sengaja tidak diubah). Tinjau: hapus bila sisa data lama,
--    atau kirim ke saya bila perlu dipasangkan ke baris anggaran tertentu.
SELECT k.tahun, k.kode_rekening, k.tahapan,
       count(*) AS jumlah_baris, sum(k.nominal) AS total_nominal
FROM public.kas_anggaran k
WHERE left(k.kode_rekening, 18) = '4.01.01.2.09.0001.'
GROUP BY k.tahun, k.kode_rekening, k.tahapan
ORDER BY k.tahun, k.kode_rekening, k.tahapan;

-- Pemulihan: data asli tersimpan di bak_20261024_anggaran / _realisasi / _kas_anggaran
-- (kolom sama, kunci id). Bila perlu dikembalikan, minta dibuatkan skrip UPDATE berdasarkan id;
-- jangan memakai TRUNCATE karena ada foreign key.
