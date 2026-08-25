-- ============================================================
-- SIANGGARAN — Perbaikan nama_belanja yang salah
-- Sub Kegiatan: 4.01.01.2.09.0002
--   "Penyediaan Jasa Pemeliharaan, Biaya Pemeliharaan, Pajak
--    dan Perizinan Kendaraan Dinas Operasional atau Lapangan"
--
-- Kode rekening (kode_belanja) 5.1.02.01.004.00035 dan
-- 5.1.02.01.004.00038 tersimpan dengan nama_belanja yang salah.
-- Kode rekening TIDAK diubah — hanya nama_belanja diperbaiki,
-- agar tidak merusak relasi ke kas_anggaran (yang dikunci per
-- kode_rekening) maupun histori realisasi.
--
-- Jalankan di Supabase SQL Editor.
-- ============================================================

-- STEP 0: CEK DATA SEBELUM DIUBAH (opsional, untuk verifikasi)
SELECT id, tahun, kode_sub_kegiatan, kode_belanja, nama_belanja, kode_rekening, sumber_dana
FROM public.anggaran
WHERE kode_sub_kegiatan = '4.01.01.2.09.0002'
  AND kode_belanja IN ('5.1.02.01.004.00035', '5.1.02.01.004.00038');

SELECT id, tahun, kode_sub_kegiatan, kode_belanja, nama_belanja, kode_rekening, sumber_dana
FROM public.realisasi
WHERE kode_sub_kegiatan = '4.01.01.2.09.0002'
  AND kode_belanja IN ('5.1.02.01.004.00035', '5.1.02.01.004.00038');


-- STEP 1: PERBAIKI TABEL anggaran
UPDATE public.anggaran
SET nama_belanja = 'Belanja Pemeliharaan Alat Angkutan-Alat Angkutan Darat Bermotor-Kendaraan Dinas Bermotor Perorangan'
WHERE kode_sub_kegiatan = '4.01.01.2.09.0002'
  AND kode_belanja = '5.1.02.01.004.00035';

UPDATE public.anggaran
SET nama_belanja = 'Belanja Pemeliharaan Alat Angkutan-Alat Angkutan Darat Bermotor-Kendaraan Bermotor Beroda Dua'
WHERE kode_sub_kegiatan = '4.01.01.2.09.0002'
  AND kode_belanja = '5.1.02.01.004.00038';


-- STEP 2: PERBAIKI TABEL realisasi (jika ada transaksi dengan kode_belanja yang sama)
UPDATE public.realisasi
SET nama_belanja = 'Belanja Pemeliharaan Alat Angkutan-Alat Angkutan Darat Bermotor-Kendaraan Dinas Bermotor Perorangan'
WHERE kode_sub_kegiatan = '4.01.01.2.09.0002'
  AND kode_belanja = '5.1.02.01.004.00035';

UPDATE public.realisasi
SET nama_belanja = 'Belanja Pemeliharaan Alat Angkutan-Alat Angkutan Darat Bermotor-Kendaraan Bermotor Beroda Dua'
WHERE kode_sub_kegiatan = '4.01.01.2.09.0002'
  AND kode_belanja = '5.1.02.01.004.00038';


-- STEP 3: VERIFIKASI HASIL PERBAIKAN
SELECT id, tahun, kode_sub_kegiatan, kode_belanja, nama_belanja, kode_rekening, sumber_dana
FROM public.anggaran
WHERE kode_sub_kegiatan = '4.01.01.2.09.0002'
  AND kode_belanja IN ('5.1.02.01.004.00035', '5.1.02.01.004.00038');


-- ============================================================
-- STEP 4: PERIKSA KEMUNGKINAN DUPLIKASI KODE REKENING / NAMA
-- BELANJA DI SELURUH DATA (jalankan dan periksa hasilnya)
-- ============================================================

-- 4a. kode_rekening yang muncul lebih dari satu kali pada anggaran
-- (seharusnya unik per kombinasi sub kegiatan+belanja+sumber dana)
SELECT kode_rekening, COUNT(*) AS jumlah_baris
FROM public.anggaran
GROUP BY kode_rekening
HAVING COUNT(*) > 1
ORDER BY jumlah_baris DESC;

-- 4b. kode_belanja yang sama tapi nama_belanja berbeda-beda pada anggaran
-- (indikasi salah ketik / salah pilih master, seperti kasus di atas)
SELECT kode_belanja, COUNT(DISTINCT nama_belanja) AS jumlah_nama_berbeda,
       string_agg(DISTINCT nama_belanja, ' | ') AS daftar_nama
FROM public.anggaran
GROUP BY kode_belanja
HAVING COUNT(DISTINCT nama_belanja) > 1;

-- 4c. sama seperti 4b tapi untuk tabel realisasi
SELECT kode_belanja, COUNT(DISTINCT nama_belanja) AS jumlah_nama_berbeda,
       string_agg(DISTINCT nama_belanja, ' | ') AS daftar_nama
FROM public.realisasi
GROUP BY kode_belanja
HAVING COUNT(DISTINCT nama_belanja) > 1;

-- 4d. kode_rekening yang sama antara anggaran dan realisasi tapi
-- nama_belanja-nya berbeda (indikasi salah satu tidak ter-update)
SELECT a.kode_rekening, a.nama_belanja AS nama_di_anggaran,
       r.nama_belanja AS nama_di_realisasi
FROM public.anggaran a
JOIN public.realisasi r ON r.kode_rekening = a.kode_rekening
WHERE a.nama_belanja IS DISTINCT FROM r.nama_belanja;
