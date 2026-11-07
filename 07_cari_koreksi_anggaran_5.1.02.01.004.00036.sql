-- ============================================================================
-- SIANGGARAN — Cari & koreksi salah input pada Input Anggaran
-- Belanja : 5.1.02.01.004.00036  (Belanja Kendaraan Bermotor Penumpang)
-- Gejala  : pagu bertambah (kelebihan) + saat diedit muncul galat
--           'update or delete on table "anggaran" violates foreign key
--            constraint "realisasi_anggaran_fkey" on table "realisasi"'
--
-- CARA PAKAI: Supabase > SQL Editor. Jalankan BAGIAN 1–6 (semuanya SELECT,
-- aman, tidak mengubah data) satu per satu. Setelah baris yang salah ketemu,
-- baru gunakan BAGIAN 7 (koreksi) — HAPUS tanda "-- " pada blok yang dipilih.
-- ============================================================================


-- ============================================================================
-- BAGIAN 1 — Definisi foreign key yang menolak perubahan (untuk dipahami)
-- Kolom yang tertulis di FOREIGN KEY (...) = kolom "kunci": tidak boleh
-- berubah selama masih ada baris realisasi yang memakainya.
-- ============================================================================
SELECT conname, conrelid::regclass AS tabel_anak, pg_get_constraintdef(oid) AS definisi
FROM pg_constraint
WHERE conname IN ('realisasi_anggaran_fkey', 'kas_anggaran_anggaran_fkey');


-- ============================================================================
-- BAGIAN 2 — SEMUA baris anggaran untuk belanja ini (semua tahun)
-- Cari: baris ganda, sumber dana berbeda, sub kegiatan salah, atau pagu janggal.
-- 'selisih' negatif = realisasi melebihi pagu terakhir.
-- ============================================================================
SELECT a.id,
       a.tahun,
       a.kode_sub_kegiatan,
       a.kode_belanja,
       a.sumber_dana,
       a.pptk,
       a.kode_rekening,
       a.pagu_murni,
       a.pagu_pergeseran,
       a.pagu_perubahan,
       COALESCE(a.pagu_perubahan, a.pagu_pergeseran, a.pagu_murni, 0)       AS pagu_terakhir,
       COALESCE(r.jml, 0)                                                   AS jml_realisasi,
       COALESCE(r.total, 0)                                                 AS total_realisasi,
       COALESCE(a.pagu_perubahan, a.pagu_pergeseran, a.pagu_murni, 0)
         - COALESCE(r.total, 0)                                             AS selisih,
       a.created_at
FROM public.anggaran a
LEFT JOIN (
  SELECT tahun, kode_rekening, count(*) AS jml, sum(nominal) AS total
  FROM public.realisasi
  GROUP BY tahun, kode_rekening
) r ON r.tahun = a.tahun AND r.kode_rekening = a.kode_rekening
WHERE a.kode_belanja = '5.1.02.01.004.00036'
   OR a.kode_rekening LIKE '%5.1.02.01.004.00036%'
ORDER BY a.tahun, a.kode_sub_kegiatan, a.created_at;


-- ============================================================================
-- BAGIAN 3 — Baris yang kode_rekening-nya TIDAK sesuai rumus aplikasi
-- (kode_sub_kegiatan.kode_belanja.sumber_dana dengan spasi -> "_").
-- Inilah penyebab paling mungkin galat foreign key: saat Simpan, aplikasi lama
-- menghitung ulang kode_rekening; bila hasilnya beda dari yang tersimpan,
-- kunci berubah dan ditolak karena sudah ada realisasi.
-- ============================================================================
SELECT id, tahun, kode_sub_kegiatan, kode_belanja, sumber_dana, kode_rekening,
       kode_sub_kegiatan || '.' || kode_belanja || '.' ||
         regexp_replace(COALESCE(sumber_dana, ''), '\s+', '_', 'g')  AS kode_menurut_aplikasi
FROM public.anggaran
WHERE kode_rekening IS DISTINCT FROM
      (kode_sub_kegiatan || '.' || kode_belanja || '.' ||
         regexp_replace(COALESCE(sumber_dana, ''), '\s+', '_', 'g'))
ORDER BY tahun, kode_rekening;

-- Sumber dana di luar daftar form (PAD / DBH CHT) — form lama gagal memilihnya
SELECT sumber_dana, count(*) AS jumlah
FROM public.anggaran
GROUP BY sumber_dana
ORDER BY jumlah DESC;


-- ============================================================================
-- BAGIAN 4 — Input TERBARU (urut waktu input). Salah input biasanya ada di atas.
-- (tabel anggaran tidak punya kolom updated_at, jadi pakai created_at)
-- ============================================================================
SELECT id, tahun, created_at, kode_sub_kegiatan, kode_belanja, sumber_dana, pptk,
       pagu_murni, pagu_pergeseran, pagu_perubahan, kode_rekening
FROM public.anggaran
ORDER BY created_at DESC
LIMIT 30;


-- ============================================================================
-- BAGIAN 5 — Bandingkan dengan cadangan 24 Okt 2026 (dibuat skrip 05).
-- Menampilkan baris yang BARU, DIHAPUS, atau PAGU-nya BERUBAH sejak cadangan.
-- Jalankan hanya jika baris pertama (cek) menghasilkan nama tabel, bukan NULL.
-- ============================================================================
SELECT to_regclass('public.bak_20261024_anggaran') AS tabel_cadangan_ada;

-- Jika ada, jalankan (hapus tanda "-- " di bawah ini):
-- SELECT CASE WHEN b.id IS NULL THEN 'BARU sejak cadangan'
--             WHEN n.id IS NULL THEN 'DIHAPUS sejak cadangan'
--             ELSE 'PAGU BERUBAH' END                     AS status,
--        COALESCE(n.id, b.id)                             AS id,
--        COALESCE(n.kode_rekening, b.kode_rekening)       AS kode_rekening,
--        b.pagu_murni AS murni_lama,  n.pagu_murni AS murni_kini,
--        b.pagu_pergeseran AS geser_lama, n.pagu_pergeseran AS geser_kini,
--        b.pagu_perubahan AS ubah_lama,  n.pagu_perubahan AS ubah_kini,
--        n.created_at
-- FROM public.anggaran n
-- FULL JOIN public.bak_20261024_anggaran b ON b.id = n.id
-- WHERE b.id IS NULL OR n.id IS NULL
--    OR (n.pagu_murni, n.pagu_pergeseran, n.pagu_perubahan)
--       IS DISTINCT FROM (b.pagu_murni, b.pagu_pergeseran, b.pagu_perubahan)
-- ORDER BY 1, n.created_at DESC NULLS LAST
-- LIMIT 100;


-- ============================================================================
-- BAGIAN 6 — Semua rekening yang realisasinya MELEBIHI pagu terakhir
-- (menunjukkan "kelebihan anggaran" di rekening mana saja, bukan hanya satu).
-- ============================================================================
SELECT a.tahun, a.kode_rekening, a.sumber_dana, a.pptk,
       COALESCE(a.pagu_perubahan, a.pagu_pergeseran, a.pagu_murni, 0) AS pagu_terakhir,
       COALESCE(r.total, 0)                                           AS total_realisasi,
       COALESCE(r.total, 0)
         - COALESCE(a.pagu_perubahan, a.pagu_pergeseran, a.pagu_murni, 0) AS kelebihan
FROM public.anggaran a
JOIN (
  SELECT tahun, kode_rekening, sum(nominal) AS total
  FROM public.realisasi
  GROUP BY tahun, kode_rekening
) r ON r.tahun = a.tahun AND r.kode_rekening = a.kode_rekening
WHERE COALESCE(r.total, 0) >
      COALESCE(a.pagu_perubahan, a.pagu_pergeseran, a.pagu_murni, 0)
ORDER BY kelebihan DESC;


-- ============================================================================
-- BAGIAN 7 — KOREKSI (jalankan SETELAH baris yang salah dipastikan dari 2–6)
-- Ganti '<ID_BARIS>' dengan nilai kolom id dari hasil BAGIAN 2/5.
-- Setiap blok berdiri sendiri, transaksi, dan membuat cadangan lebih dulu.
-- ============================================================================

-- ---- 7A. Pagu salah angka pada baris yang BENAR (kasus paling umum) --------
-- Hanya kolom pagu yang diubah (BUKAN kolom kunci), jadi foreign key tidak
-- terganggu walaupun realisasi sudah ada. Isi hanya kolom tahapan yang salah;
-- kolom lain biarkan sama dengan hasil BAGIAN 2 (NULL = ikut tahapan sebelumnya).
--
-- BEGIN;
-- CREATE TABLE IF NOT EXISTS public.bak_20261107_anggaran AS SELECT * FROM public.anggaran;
-- ALTER TABLE public.bak_20261107_anggaran ENABLE ROW LEVEL SECURITY;
--
-- UPDATE public.anggaran
-- SET pagu_murni      = 0,      -- <- isi nilai yang benar
--     pagu_pergeseran = NULL,   -- <- isi nilai yang benar atau NULL
--     pagu_perubahan  = NULL    -- <- isi nilai yang benar atau NULL
-- WHERE id = '<ID_BARIS>'
-- RETURNING id, kode_rekening, pagu_murni, pagu_pergeseran, pagu_perubahan;
--
-- COMMIT;   -- bila hasil RETURNING sudah benar. Jika ragu: ganti dengan ROLLBACK;


-- ---- 7B. Baris SALAH / GANDA yang harus dihapus ----------------------------
-- Aman hanya bila baris itu belum punya realisasi. Pengaman di bawah membuat
-- DELETE tidak jalan (0 baris) bila masih ada realisasi yang memakainya.
-- Anggaran kas baris itu ikut dibersihkan (kas_anggaran memakai soft-delete
-- pada aplikasi; di sini dihapus permanen karena induknya dihapus).
--
-- BEGIN;
-- CREATE TABLE IF NOT EXISTS public.bak_20261107_anggaran     AS SELECT * FROM public.anggaran;
-- CREATE TABLE IF NOT EXISTS public.bak_20261107_kas_anggaran AS SELECT * FROM public.kas_anggaran;
-- ALTER TABLE public.bak_20261107_anggaran     ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE public.bak_20261107_kas_anggaran ENABLE ROW LEVEL SECURITY;
--
-- DELETE FROM public.kas_anggaran k
-- USING public.anggaran a
-- WHERE a.id = '<ID_BARIS>'
--   AND k.tahun = a.tahun AND k.kode_rekening = a.kode_rekening
--   AND NOT EXISTS (SELECT 1 FROM public.realisasi r
--                   WHERE r.tahun = a.tahun AND r.kode_rekening = a.kode_rekening);
--
-- DELETE FROM public.anggaran a
-- WHERE a.id = '<ID_BARIS>'
--   AND NOT EXISTS (SELECT 1 FROM public.realisasi r
--                   WHERE r.tahun = a.tahun AND r.kode_rekening = a.kode_rekening)
-- RETURNING a.id, a.kode_rekening;
--
-- COMMIT;   -- RETURNING kosong = baris tidak dihapus karena masih ada realisasi


-- ---- 7C. Realisasi terlanjur tercatat di baris SALAH -----------------------
-- Pindahkan realisasi ke kode_rekening baris yang BENAR (keduanya sudah ada
-- di tabel anggaran, tahun sama), lalu hapus baris salah dengan 7B.
--
-- BEGIN;
-- CREATE TABLE IF NOT EXISTS public.bak_20261107_realisasi AS SELECT * FROM public.realisasi;
-- ALTER TABLE public.bak_20261107_realisasi ENABLE ROW LEVEL SECURITY;
--
-- UPDATE public.realisasi
-- SET kode_rekening     = '<KODE_REKENING_BENAR>',
--     kode_sub_kegiatan = '<KODE_SUB_KEGIATAN_BENAR>',
--     sumber_dana       = '<SUMBER_DANA_BENAR>'
-- WHERE tahun = '<TAHUN>' AND kode_rekening = '<KODE_REKENING_SALAH>'
--   -- tambahkan "AND id = '...'" bila hanya sebagian realisasi yang salah
--   AND EXISTS (SELECT 1 FROM public.anggaran
--               WHERE tahun = '<TAHUN>' AND kode_rekening = '<KODE_REKENING_BENAR>')
-- RETURNING id, tanggal, nominal, kode_rekening;
--
-- COMMIT;
