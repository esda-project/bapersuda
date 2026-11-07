-- ============================================================================
-- SIANGGARAN — Pindahkan SEMUA transaksi dari kode rekening belanja lama ke baru
--
--   LAMA : 4.01.01.2.09.0002.5.1.02.03.002.00035.PAD
--          Belanja Pemeliharaan Alat Angkutan-...-Kendaraan Dinas Bermotor Perorangan
--          (kode_belanja 5.1.02.03.002.00035)
--   BARU : 4.01.01.2.09.0002.5.1.02.01.004.00036.PAD
--          Belanja Peralatan dan Mesin-Alat Angkutan-Alat Angkutan Darat Bermotor-
--          Kendaraan Bermotor Penumpang (kode_belanja 5.1.02.01.004.00036)
--
-- Sub kegiatan (4.01.01.2.09.0002), sumber dana (PAD) dan PPTK TIDAK berubah;
-- hanya kode_belanja, nama_belanja dan kode_rekening.
--
-- KENAPA TIDAK BISA DARI APLIKASI: 11 data Realisasi (dan Anggaran Kas) menunjuk ke
-- kode_rekening lama lewat foreign key (realisasi_anggaran_fkey). Mengubah satu sisi
-- saja ditolak. Skrip ini mengubah ketiga tabel dalam SATU transaksi dengan
-- foreign key dilepas SEMENTARA di dalam transaksi itu lalu dipasang kembali dengan
-- definisi yang sama persis (dicatat otomatis dari database, divalidasi ulang saat dipasang).
-- (Menunda pengecekan tidak cukup: foreign key ini bertipe RESTRICT, yang selalu dicek langsung.)
--
-- URUTAN: (1) jalankan BAGIAN 1 (pratinjau, SELECT saja) dan baca hasilnya;
--         (2) jalankan BAGIAN 2 (perubahan) — satu transaksi, gagal = batal total.
-- Bila tahun/kode berbeda, ubah nilai di BAGIAN 1 dan BAGIAN 2 secara SAMA.
-- ============================================================================


-- ============================================================================
-- BAGIAN 1 — PRATINJAU (aman, tidak mengubah apa pun)
-- ============================================================================

-- 1a. Baris anggaran: rekening LAMA dan rekening TUJUAN (bila sudah ada)
SELECT CASE WHEN a.kode_rekening = '4.01.01.2.09.0002.5.1.02.03.002.00035.PAD'
            THEN 'LAMA (akan dipindah)' ELSE 'TUJUAN (sudah ada)' END AS peran,
       a.id, a.tahun, a.kode_rekening, a.kode_belanja, a.sumber_dana, a.pptk,
       a.pagu_murni, a.pagu_pergeseran, a.pagu_perubahan
FROM public.anggaran a
WHERE a.tahun = '2026'
  AND a.kode_rekening IN ('4.01.01.2.09.0002.5.1.02.03.002.00035.PAD',
                          '4.01.01.2.09.0002.5.1.02.01.004.00036.PAD');

-- 1b. Semua rekening ber-belanja lama (bila ada sumber dana lain, mis. DBH CHT,
--     skrip ini perlu dijalankan lagi untuk rekening tersebut)
SELECT id, kode_rekening, sumber_dana, pagu_murni, pagu_pergeseran, pagu_perubahan
FROM public.anggaran
WHERE tahun = '2026' AND kode_belanja = '5.1.02.03.002.00035';

-- 1c. Jumlah & total realisasi per rekening (LAMA harus 11 data)
SELECT kode_rekening, count(*) AS jml_realisasi, sum(nominal) AS total_realisasi
FROM public.realisasi
WHERE tahun = '2026'
  AND kode_rekening IN ('4.01.01.2.09.0002.5.1.02.03.002.00035.PAD',
                        '4.01.01.2.09.0002.5.1.02.01.004.00036.PAD')
GROUP BY kode_rekening;

-- 1d. Baris anggaran kas per rekening
SELECT kode_rekening, count(*) AS jml_baris_kas
FROM public.kas_anggaran
WHERE tahun = '2026'
  AND kode_rekening IN ('4.01.01.2.09.0002.5.1.02.03.002.00035.PAD',
                        '4.01.01.2.09.0002.5.1.02.01.004.00036.PAD')
GROUP BY kode_rekening;

-- 1e. Total pagu belanja tujuan SAAT INI (target akhir: 781.989.691)
SELECT sum(COALESCE(pagu_murni, 0))                                   AS total_murni,
       sum(COALESCE(pagu_pergeseran, pagu_murni, 0))                  AS total_pergeseran,
       sum(COALESCE(pagu_perubahan, pagu_pergeseran, pagu_murni, 0))  AS total_perubahan
FROM public.anggaran
WHERE tahun = '2026' AND kode_belanja = '5.1.02.01.004.00036';

-- BACA HASIL:
--  * 1a hanya baris LAMA  -> BAGIAN 2 akan MENGGANTI KODE baris itu (pagu ikut pindah ke belanja baru).
--                            Total di 1e akan naik sebesar pagu baris LAMA. Pastikan itu yang Anda maksud.
--                            (Bila pagu baris LAMA = 33.600.000, itu kemungkinan sumber kelebihan.)
--  * 1a ada LAMA + TUJUAN -> BAGIAN 2 hanya memindahkan 11 realisasi ke rekening TUJUAN. Baris anggaran
--                            LAMA (dan pagunya) dibiarkan agar Anda putuskan sendiri (hapus/koreksi) sesudahnya.


-- ============================================================================
-- BAGIAN 2 — PERUBAHAN (satu transaksi; bila ada yang tidak cocok, semuanya batal)
-- ============================================================================
BEGIN;

-- Parameter (samakan dengan BAGIAN 1)
CREATE TEMP TABLE _p ON COMMIT DROP AS
SELECT t.*, replace(t.rek_lama, t.bel_lama, t.bel_baru) AS rek_baru
FROM (SELECT '2026'::text                                     AS tahun,
             '4.01.01.2.09.0002.5.1.02.03.002.00035.PAD'::text AS rek_lama,
             '5.1.02.03.002.00035'::text                      AS bel_lama,
             '5.1.02.01.004.00036'::text                      AS bel_baru,
             'Belanja Peralatan dan Mesin-Alat Angkutan-Alat Angkutan Darat Bermotor-Kendaraan Bermotor Penumpang'::text AS nama_baru) t;

-- Cadangan (RLS aktif tanpa kebijakan = tertutup dari API)
CREATE TABLE IF NOT EXISTS public.bak_20261107_pindah_anggaran     AS SELECT * FROM public.anggaran;
CREATE TABLE IF NOT EXISTS public.bak_20261107_pindah_realisasi    AS SELECT * FROM public.realisasi;
CREATE TABLE IF NOT EXISTS public.bak_20261107_pindah_kas_anggaran AS SELECT * FROM public.kas_anggaran;
ALTER TABLE public.bak_20261107_pindah_anggaran     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bak_20261107_pindah_realisasi    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bak_20261107_pindah_kas_anggaran ENABLE ROW LEVEL SECURITY;

-- Catat definisi foreign key, lalu lepaskan SEMENTARA (dipasang kembali di akhir transaksi).
-- Bila transaksi gagal di tengah jalan, semuanya (termasuk pelepasan ini) dibatalkan otomatis.
CREATE TEMP TABLE _fk ON COMMIT DROP AS
SELECT c.conname,
       c.conrelid::regclass::text AS tabel,
       pg_get_constraintdef(c.oid) AS def
FROM pg_constraint c
WHERE c.contype = 'f'
  AND c.conname IN ('realisasi_anggaran_fkey', 'kas_anggaran_anggaran_fkey');

DO $$
DECLARE f record;
BEGIN
  FOR f IN SELECT * FROM _fk LOOP
    EXECUTE format('ALTER TABLE %s DROP CONSTRAINT %I', f.tabel, f.conname);
  END LOOP;
END $$;

-- Pemindahan (foreign key sedang dilepas)
DO $$
DECLARE
  p        record;
  ada_baru boolean;
  n_ang    int := 0;
  n_real   int := 0;
  n_kas    int := 0;
  bentrok  int;
BEGIN
  SELECT * INTO p FROM _p;

  IF NOT EXISTS (SELECT 1 FROM public.anggaran WHERE tahun = p.tahun AND kode_rekening = p.rek_lama) THEN
    RAISE EXCEPTION 'DIBATALKAN: baris anggaran % (TA %) tidak ditemukan. Tidak ada data yang diubah.', p.rek_lama, p.tahun;
  END IF;

  SELECT EXISTS (SELECT 1 FROM public.anggaran WHERE tahun = p.tahun AND kode_rekening = p.rek_baru)
    INTO ada_baru;

  IF ada_baru THEN
    -- Rekening tujuan sudah ada: pindahkan REALISASI saja; anggaran & kas lama dibiarkan.
    UPDATE public.realisasi
       SET kode_rekening = p.rek_baru, kode_belanja = p.bel_baru, nama_belanja = p.nama_baru
     WHERE tahun = p.tahun AND kode_rekening = p.rek_lama;
    GET DIAGNOSTICS n_real = ROW_COUNT;
    RAISE NOTICE 'Rekening tujuan sudah ada. % realisasi dipindah; baris anggaran & kas lama TIDAK diubah.', n_real;

  ELSE
    -- Rekening tujuan belum ada: ganti kode baris anggaran LAMA, realisasi, dan kas.
    SELECT count(*) INTO bentrok FROM public.kas_anggaran
     WHERE tahun = p.tahun AND kode_rekening = p.rek_baru;
    IF bentrok > 0 THEN
      RAISE EXCEPTION 'DIBATALKAN: % baris kas_anggaran sudah memakai kode tujuan %. Tidak ada data yang diubah.', bentrok, p.rek_baru;
    END IF;

    UPDATE public.anggaran
       SET kode_belanja = p.bel_baru, nama_belanja = p.nama_baru, kode_rekening = p.rek_baru
     WHERE tahun = p.tahun AND kode_rekening = p.rek_lama;
    GET DIAGNOSTICS n_ang = ROW_COUNT;

    UPDATE public.realisasi
       SET kode_rekening = p.rek_baru, kode_belanja = p.bel_baru, nama_belanja = p.nama_baru
     WHERE tahun = p.tahun AND kode_rekening = p.rek_lama;
    GET DIAGNOSTICS n_real = ROW_COUNT;

    UPDATE public.kas_anggaran
       SET kode_rekening = p.rek_baru
     WHERE tahun = p.tahun AND kode_rekening = p.rek_lama;     -- semua tahapan & bulan, termasuk soft-delete
    GET DIAGNOSTICS n_kas = ROW_COUNT;

    RAISE NOTICE 'Kode diganti: % baris anggaran, % realisasi, % baris kas.', n_ang, n_real, n_kas;
  END IF;
END $$;

-- Pasang kembali foreign key (definisi sama persis; seluruh baris divalidasi ulang di sini —
-- bila ada data yatim, transaksi gagal dan semuanya dibatalkan)
DO $$
DECLARE f record;
BEGIN
  FOR f IN SELECT * FROM _fk LOOP
    EXECUTE format('ALTER TABLE %s ADD CONSTRAINT %I %s', f.tabel, f.conname, f.def);
  END LOOP;
END $$;

-- Verifikasi: tidak boleh ada realisasi tersisa di rekening lama
DO $$
DECLARE p record; n int;
BEGIN
  SELECT * INTO p FROM _p;
  SELECT count(*) INTO n FROM public.realisasi WHERE tahun = p.tahun AND kode_rekening = p.rek_lama;
  IF n > 0 THEN
    RAISE EXCEPTION 'DIBATALKAN: masih ada % realisasi di rekening lama.', n;
  END IF;
END $$;

COMMIT;


-- ============================================================================
-- BAGIAN 3 — HASIL (jalankan terpisah setelah COMMIT)
-- ============================================================================

-- 3a. Realisasi di rekening baru (harus 11 data)
SELECT kode_rekening, kode_belanja, nama_belanja, count(*) AS jml, sum(nominal) AS total_nominal
FROM public.realisasi
WHERE tahun = '2026' AND kode_rekening = '4.01.01.2.09.0002.5.1.02.01.004.00036.PAD'
GROUP BY 1, 2, 3;

-- 3b. Total pagu belanja 5.1.02.01.004.00036 (bandingkan dengan target 781.989.691)
SELECT sum(COALESCE(pagu_murni, 0))                                   AS total_murni,
       sum(COALESCE(pagu_pergeseran, pagu_murni, 0))                  AS total_pergeseran,
       sum(COALESCE(pagu_perubahan, pagu_pergeseran, pagu_murni, 0))  AS total_perubahan
FROM public.anggaran
WHERE tahun = '2026' AND kode_belanja = '5.1.02.01.004.00036';

-- Pemulihan bila perlu: data asli ada di bak_20261107_pindah_anggaran / _realisasi / _kas_anggaran
-- (kolom sama, kunci id). Minta dibuatkan skrip UPDATE berdasarkan id; jangan memakai TRUNCATE.
