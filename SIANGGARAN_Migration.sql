-- ============================================================
-- SIANGGARAN — Full Migration Script untuk Supabase
-- Bagian Perekonomian dan Sumber Daya Alam
-- ============================================================
-- PETUNJUK PENGGUNAAN:
--   1. Buka https://supabase.com/dashboard/project/ryevqkcfrugyenfisvoh/sql
--   2. Hapus semua isi editor, paste seluruh isi file ini
--   3. Klik "Run" — script ini AMAN dijalankan berulang kali
--      (tidak akan menghapus data yang sudah ada)
-- ============================================================


-- ============================================================
-- LANGKAH 1: HAPUS TABEL LAMA (JIKA STRUKTUR BERBEDA)
-- ============================================================
-- PERINGATAN: Uncomment blok DROP di bawah HANYA jika ingin
-- reset total dan mulai dari awal (semua data akan terhapus).
-- Jika hanya ingin menambah kolom yang kurang, lewati bagian ini.

/*
DROP TABLE IF EXISTS kas_anggaran CASCADE;
DROP TABLE IF EXISTS realisasi CASCADE;
DROP TABLE IF EXISTS anggaran CASCADE;
DROP TABLE IF EXISTS pengguna CASCADE;
DROP TABLE IF EXISTS app_settings CASCADE;
*/


-- ============================================================
-- LANGKAH 2: BUAT SEMUA TABEL
-- ============================================================

-- Tabel pengguna (login custom, bukan Supabase Auth)
CREATE TABLE IF NOT EXISTS pengguna (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  nama        TEXT        NOT NULL,
  username    TEXT        UNIQUE NOT NULL,
  password    TEXT        NOT NULL,
  role        TEXT        NOT NULL DEFAULT 'input'
                          CHECK (role IN ('admin','input','view')),
  jabatan     TEXT,
  created_at  TIMESTAMPTZ DEFAULT now()
);

-- Tabel anggaran (pagu per rekening per tahun)
CREATE TABLE IF NOT EXISTS anggaran (
  id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  tahun               TEXT        NOT NULL,
  kode_program        TEXT,
  program             TEXT,
  kode_kegiatan       TEXT,
  kegiatan            TEXT,
  kode_sub_kegiatan   TEXT,
  sub_kegiatan        TEXT,
  kode_belanja        TEXT,
  nama_belanja        TEXT,
  kode_rekening       TEXT        NOT NULL,
  pagu_murni          NUMERIC     DEFAULT 0,
  pagu_pergeseran     NUMERIC,
  pagu_perubahan      NUMERIC,
  sumber_dana         TEXT,
  pptk                TEXT,
  created_at          TIMESTAMPTZ DEFAULT now()
);

-- Tabel realisasi (transaksi belanja)
CREATE TABLE IF NOT EXISTS realisasi (
  id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  tahun               TEXT        NOT NULL,
  tanggal             DATE,
  tanggal_sp2d        DATE,
  uraian              TEXT,
  kode_sub_kegiatan   TEXT,
  kode_belanja        TEXT,
  sumber_dana         TEXT,
  kode_rekening       TEXT,
  nama_belanja        TEXT,
  nominal             NUMERIC     DEFAULT 0,
  pptk                TEXT,
  created_at          TIMESTAMPTZ DEFAULT now()
);

-- Tabel kas anggaran (rencana penyerapan per bulan, disimpan sebagai JSON)
CREATE TABLE IF NOT EXISTS kas_anggaran (
  id              TEXT        PRIMARY KEY,   -- format: "{tahun}_{kode_rekening}"
  tahun           TEXT        NOT NULL,
  kode_rekening   TEXT        NOT NULL,
  data            JSONB       DEFAULT '{}',  -- {jan:0, feb:0, ..., des:0}
  UNIQUE (tahun, kode_rekening)
);

-- Tabel pengaturan aplikasi (opsional, untuk konfigurasi dinamis)
CREATE TABLE IF NOT EXISTS app_settings (
  key     TEXT PRIMARY KEY,
  value   TEXT
);


-- ============================================================
-- LANGKAH 3: PATCH KOLOM — tambah kolom yang mungkin belum ada
-- (Aman dijalankan pada tabel lama yang sudah berisi data)
-- ============================================================
DO $$
BEGIN
  -- Patch tabel anggaran
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_name='anggaran' AND column_name='tahun') THEN
    ALTER TABLE anggaran ADD COLUMN tahun TEXT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_name='anggaran' AND column_name='kode_program') THEN
    ALTER TABLE anggaran ADD COLUMN kode_program TEXT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_name='anggaran' AND column_name='program') THEN
    ALTER TABLE anggaran ADD COLUMN program TEXT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_name='anggaran' AND column_name='kode_kegiatan') THEN
    ALTER TABLE anggaran ADD COLUMN kode_kegiatan TEXT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_name='anggaran' AND column_name='kegiatan') THEN
    ALTER TABLE anggaran ADD COLUMN kegiatan TEXT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_name='anggaran' AND column_name='kode_sub_kegiatan') THEN
    ALTER TABLE anggaran ADD COLUMN kode_sub_kegiatan TEXT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_name='anggaran' AND column_name='sub_kegiatan') THEN
    ALTER TABLE anggaran ADD COLUMN sub_kegiatan TEXT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_name='anggaran' AND column_name='kode_belanja') THEN
    ALTER TABLE anggaran ADD COLUMN kode_belanja TEXT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_name='anggaran' AND column_name='nama_belanja') THEN
    ALTER TABLE anggaran ADD COLUMN nama_belanja TEXT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_name='anggaran' AND column_name='kode_rekening') THEN
    ALTER TABLE anggaran ADD COLUMN kode_rekening TEXT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_name='anggaran' AND column_name='pagu_murni') THEN
    ALTER TABLE anggaran ADD COLUMN pagu_murni NUMERIC DEFAULT 0;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_name='anggaran' AND column_name='pagu_pergeseran') THEN
    ALTER TABLE anggaran ADD COLUMN pagu_pergeseran NUMERIC;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_name='anggaran' AND column_name='pagu_perubahan') THEN
    ALTER TABLE anggaran ADD COLUMN pagu_perubahan NUMERIC;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_name='anggaran' AND column_name='sumber_dana') THEN
    ALTER TABLE anggaran ADD COLUMN sumber_dana TEXT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_name='anggaran' AND column_name='pptk') THEN
    ALTER TABLE anggaran ADD COLUMN pptk TEXT;
  END IF;

  -- Patch tabel realisasi
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_name='realisasi' AND column_name='tahun') THEN
    ALTER TABLE realisasi ADD COLUMN tahun TEXT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_name='realisasi' AND column_name='tanggal') THEN
    ALTER TABLE realisasi ADD COLUMN tanggal DATE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_name='realisasi' AND column_name='tanggal_sp2d') THEN
    ALTER TABLE realisasi ADD COLUMN tanggal_sp2d DATE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_name='realisasi' AND column_name='uraian') THEN
    ALTER TABLE realisasi ADD COLUMN uraian TEXT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_name='realisasi' AND column_name='kode_sub_kegiatan') THEN
    ALTER TABLE realisasi ADD COLUMN kode_sub_kegiatan TEXT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_name='realisasi' AND column_name='kode_belanja') THEN
    ALTER TABLE realisasi ADD COLUMN kode_belanja TEXT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_name='realisasi' AND column_name='sumber_dana') THEN
    ALTER TABLE realisasi ADD COLUMN sumber_dana TEXT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_name='realisasi' AND column_name='kode_rekening') THEN
    ALTER TABLE realisasi ADD COLUMN kode_rekening TEXT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_name='realisasi' AND column_name='nama_belanja') THEN
    ALTER TABLE realisasi ADD COLUMN nama_belanja TEXT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_name='realisasi' AND column_name='nominal') THEN
    ALTER TABLE realisasi ADD COLUMN nominal NUMERIC DEFAULT 0;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_name='realisasi' AND column_name='pptk') THEN
    ALTER TABLE realisasi ADD COLUMN pptk TEXT;
  END IF;

  -- Patch tabel pengguna
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_name='pengguna' AND column_name='jabatan') THEN
    ALTER TABLE pengguna ADD COLUMN jabatan TEXT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_name='pengguna' AND column_name='role') THEN
    ALTER TABLE pengguna ADD COLUMN role TEXT NOT NULL DEFAULT 'input';
  END IF;

  RAISE NOTICE 'Patch selesai — semua kolom sudah tersedia.';
END $$;


-- ============================================================
-- LANGKAH 4: NONAKTIFKAN ROW LEVEL SECURITY
-- (aplikasi menggunakan anon key langsung dari browser)
-- ============================================================
ALTER TABLE pengguna     DISABLE ROW LEVEL SECURITY;
ALTER TABLE anggaran     DISABLE ROW LEVEL SECURITY;
ALTER TABLE realisasi    DISABLE ROW LEVEL SECURITY;
ALTER TABLE kas_anggaran DISABLE ROW LEVEL SECURITY;
ALTER TABLE app_settings DISABLE ROW LEVEL SECURITY;


-- ============================================================
-- LANGKAH 5: GRANT AKSES KE anon ROLE
-- ============================================================
GRANT ALL ON TABLE pengguna     TO anon;
GRANT ALL ON TABLE anggaran     TO anon;
GRANT ALL ON TABLE realisasi    TO anon;
GRANT ALL ON TABLE kas_anggaran TO anon;
GRANT ALL ON TABLE app_settings TO anon;

GRANT ALL ON TABLE pengguna     TO authenticated;
GRANT ALL ON TABLE anggaran     TO authenticated;
GRANT ALL ON TABLE realisasi    TO authenticated;
GRANT ALL ON TABLE kas_anggaran TO authenticated;
GRANT ALL ON TABLE app_settings TO authenticated;


-- ============================================================
-- LANGKAH 6: DATA AWAL — Akun pengguna default
-- (ON CONFLICT DO NOTHING = aman jika sudah ada)
-- ============================================================
INSERT INTO pengguna (nama, username, password, role, jabatan)
VALUES
  ('Administrator',          'admin',  'admin123', 'admin', 'Admin Sistem'),
  ('TENGKO WOLOK, S.T.',     'tengko', 'pptk123',  'input', 'PPTK'),
  ('DIYAH WAHYUNI, S.E., M.M.', 'diyah', 'pptk123', 'input', 'PPTK'),
  ('SARI ANAS PUTRI, S.E.',  'sari',   'pptk123',  'input', 'PPTK')
ON CONFLICT (username) DO NOTHING;


-- ============================================================
-- LANGKAH 7: REFRESH SCHEMA CACHE PostgREST
-- (wajib setelah perubahan struktur tabel)
-- ============================================================
NOTIFY pgrst, 'reload schema';


-- ============================================================
-- SELESAI
-- Verifikasi dengan menjalankan query berikut:
--   SELECT table_name FROM information_schema.tables
--   WHERE table_schema = 'public' ORDER BY table_name;
-- Harus tampil: anggaran, app_settings, kas_anggaran, pengguna, realisasi
-- ============================================================
