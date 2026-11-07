-- ============================================================================
-- SIANGGARAN — Cari & batalkan kelebihan pagu Rp 33.600.000
-- Belanja : 5.1.02.01.004.00036 (Kendaraan Bermotor Penumpang)
-- Target  : total pagu SEMUA tahapan seharusnya Rp 781.989.691
--           (sekarang lebih Rp 33.600.000 = Rp 815.589.691)
--
-- CARA PAKAI: Supabase > SQL Editor. Jalankan BAGIAN 1–4 satu per satu
-- (semuanya SELECT, aman). Setelah penyebab jelas, pakai BAGIAN 5.
-- Ganti '2026' bila tahun anggarannya berbeda.
-- ============================================================================


-- ============================================================================
-- BAGIAN 1 — Total pagu belanja ini per tahapan, dibanding target
-- Aturan aplikasi: Pergeseran kosong (NULL) = ikut Murni; Perubahan kosong = ikut Pergeseran.
-- Bila ketiga angka 'kelebihan_*' = 33.600.000, kesalahan ada di SATU baris
-- yang kolom Murni-nya (atau semua tahapannya) naik 33.600.000.
-- ============================================================================
SELECT tahun,
       count(*)                                                                AS jml_baris,
       sum(COALESCE(pagu_murni, 0))                                            AS total_murni,
       sum(COALESCE(pagu_pergeseran, pagu_murni, 0))                           AS total_pergeseran,
       sum(COALESCE(pagu_perubahan, pagu_pergeseran, pagu_murni, 0))           AS total_perubahan,
       sum(COALESCE(pagu_murni, 0))                                  - 781989691 AS kelebihan_murni,
       sum(COALESCE(pagu_pergeseran, pagu_murni, 0))                 - 781989691 AS kelebihan_pergeseran,
       sum(COALESCE(pagu_perubahan, pagu_pergeseran, pagu_murni, 0)) - 781989691 AS kelebihan_perubahan
FROM public.anggaran
WHERE kode_belanja = '5.1.02.01.004.00036'
  AND tahun = '2026'
GROUP BY tahun;


-- ============================================================================
-- BAGIAN 2 — Seluruh baris belanja ini (satu baris = satu sub kegiatan + sumber dana)
-- Perhatikan: (a) baris ganda, (b) angka berakhiran selisih 33.600.000,
-- (c) baris dengan created_at paling baru.
-- ============================================================================
SELECT a.id, a.created_at, a.kode_sub_kegiatan, a.sumber_dana, a.pptk,
       a.pagu_murni, a.pagu_pergeseran, a.pagu_perubahan,
       (a.pagu_murni = 33600000 OR a.pagu_pergeseran = 33600000 OR a.pagu_perubahan = 33600000) AS ada_angka_33_6jt,
       a.kode_rekening
FROM public.anggaran a
WHERE a.kode_belanja = '5.1.02.01.004.00036'
  AND a.tahun = '2026'
ORDER BY a.created_at DESC;


-- ============================================================================
-- BAGIAN 3 — Riwayat (hanya ada bila 08_riwayat_aktivitas.sql SUDAH dijalankan
-- sebelum kejadian; bila baru dipasang sekarang, hasilnya kosong — lanjut ke 4)
-- ============================================================================
SELECT r.id AS riwayat_id, r.waktu AT TIME ZONE 'Asia/Jakarta' AS waktu_wib,
       r.username, r.nama, r.aksi, r.kolom_berubah,
       r.data_lama ->> 'pagu_murni'      AS murni_lama,  r.data_baru ->> 'pagu_murni'      AS murni_baru,
       r.data_lama ->> 'pagu_pergeseran' AS geser_lama,  r.data_baru ->> 'pagu_pergeseran' AS geser_baru,
       r.data_lama ->> 'pagu_perubahan'  AS ubah_lama,   r.data_baru ->> 'pagu_perubahan'  AS ubah_baru
FROM public.sianggaran_riwayat r
WHERE r.tabel = 'anggaran'
  AND r.kode_rekening LIKE '%5.1.02.01.004.00036%'
ORDER BY r.waktu DESC;


-- ============================================================================
-- BAGIAN 4 — Bandingkan dengan cadangan 24 Okt 2026 (skrip 05).
-- Jalankan baris pertama dulu; bila tabel ada, hapus "-- " pada query di bawahnya.
-- Hasil: baris yang BARU / DIHAPUS / PAGU-nya BERUBAH sejak cadangan.
-- ============================================================================
SELECT to_regclass('public.bak_20261024_anggaran') AS tabel_cadangan_ada;

-- SELECT CASE WHEN b.id IS NULL THEN 'BARU sejak cadangan'
--             WHEN n.id IS NULL THEN 'DIHAPUS sejak cadangan'
--             ELSE 'PAGU BERUBAH' END                  AS status,
--        COALESCE(n.id, b.id)                          AS id,
--        COALESCE(n.kode_rekening, b.kode_rekening)    AS kode_rekening,
--        b.pagu_murni AS murni_lama,       n.pagu_murni AS murni_kini,
--        b.pagu_pergeseran AS geser_lama,  n.pagu_pergeseran AS geser_kini,
--        b.pagu_perubahan AS ubah_lama,    n.pagu_perubahan AS ubah_kini,
--        COALESCE(n.pagu_murni, 0) - COALESCE(b.pagu_murni, 0) AS selisih_murni
-- FROM public.anggaran n
-- FULL JOIN public.bak_20261024_anggaran b ON b.id = n.id
-- WHERE (COALESCE(n.kode_belanja, b.kode_belanja) = '5.1.02.01.004.00036')
--   AND ( b.id IS NULL OR n.id IS NULL
--      OR (n.pagu_murni, n.pagu_pergeseran, n.pagu_perubahan)
--         IS DISTINCT FROM (b.pagu_murni, b.pagu_pergeseran, b.pagu_perubahan) );


-- ============================================================================
-- BAGIAN 5 — PEMBATALAN. Pilih SATU blok sesuai temuan, hapus "-- " pada blok itu.
-- Semua memakai transaksi, cadangan, dan pemeriksaan total = 781.989.691
-- SEBELUM COMMIT (bila total tidak cocok, skrip berhenti dan tidak mengubah apa pun).
-- Ganti '<ID_BARIS>' dengan kolom id dari BAGIAN 2.
-- ============================================================================

-- ---- 5A. SATU baris naik 33.600.000 (kasus paling umum: Pagu Murni diubah,
--          Pergeseran/Perubahan kosong sehingga ikut naik di semua tahapan) -----
-- Kurangi 33.600.000 dari setiap kolom pagu yang TERISI (kolom NULL dibiarkan NULL).
--
-- BEGIN;
-- CREATE TABLE IF NOT EXISTS public.bak_20261107_anggaran AS SELECT * FROM public.anggaran;
-- ALTER TABLE public.bak_20261107_anggaran ENABLE ROW LEVEL SECURITY;
--
-- UPDATE public.anggaran
-- SET pagu_murni      = pagu_murni - 33600000,
--     pagu_pergeseran = CASE WHEN pagu_pergeseran IS NULL THEN NULL ELSE pagu_pergeseran - 33600000 END,
--     pagu_perubahan  = CASE WHEN pagu_perubahan  IS NULL THEN NULL ELSE pagu_perubahan  - 33600000 END
-- WHERE id = '<ID_BARIS>'
-- RETURNING id, kode_rekening, pagu_murni, pagu_pergeseran, pagu_perubahan;
--
-- DO $$
-- DECLARE t_m numeric; t_g numeric; t_p numeric;
-- BEGIN
--   SELECT sum(COALESCE(pagu_murni,0)),
--          sum(COALESCE(pagu_pergeseran, pagu_murni, 0)),
--          sum(COALESCE(pagu_perubahan, pagu_pergeseran, pagu_murni, 0))
--     INTO t_m, t_g, t_p
--   FROM public.anggaran
--   WHERE kode_belanja = '5.1.02.01.004.00036' AND tahun = '2026';
--   IF t_m <> 781989691 OR t_g <> 781989691 OR t_p <> 781989691 THEN
--     RAISE EXCEPTION 'DIBATALKAN: total Murni/Pergeseran/Perubahan = % / % / % (target 781989691)', t_m, t_g, t_p;
--   END IF;
-- END $$;
--
-- COMMIT;


-- ---- 5B. Ada baris TAMBAHAN/GANDA bernilai 33.600.000 (salah input baru) -----
-- Hanya dihapus bila belum punya realisasi; anggaran kasnya ikut dibersihkan.
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
-- -- periksa total (harus 781.989.691 pada ketiga kolom), lalu COMMIT
-- SELECT sum(COALESCE(pagu_murni,0))                                  AS total_murni,
--        sum(COALESCE(pagu_pergeseran, pagu_murni, 0))                AS total_pergeseran,
--        sum(COALESCE(pagu_perubahan, pagu_pergeseran, pagu_murni, 0)) AS total_perubahan
-- FROM public.anggaran
-- WHERE kode_belanja = '5.1.02.01.004.00036' AND tahun = '2026';
--
-- COMMIT;   -- bila total belum 781.989.691, ganti dengan ROLLBACK;


-- ---- 5C. Kelebihan hanya pada SATU tahapan tertentu ---------------------------
-- (BAGIAN 1 menunjukkan kelebihan hanya di satu kolom total.) Ubah kolom itu saja:
--
-- UPDATE public.anggaran
-- SET pagu_perubahan = pagu_perubahan - 33600000      -- ganti kolom sesuai temuan
-- WHERE id = '<ID_BARIS>'
-- RETURNING id, kode_rekening, pagu_murni, pagu_pergeseran, pagu_perubahan;
