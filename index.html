-- ============================================================
-- FIX: Gagal Simpan Saat Edit Role Pengguna ke 'kpa'
-- ============================================================
-- Kemungkinan besar penyebabnya: tabel pengguna punya CHECK
-- constraint pada kolom role yang BELUM mengizinkan nilai 'kpa'.
-- Jalankan script ini untuk memastikan constraint sudah benar.
-- ============================================================

-- STEP 1: Cek constraint yang ada saat ini (jalankan dulu untuk melihat)
SELECT con.conname AS constraint_name, pg_get_constraintdef(con.oid) AS definition
FROM pg_constraint con
JOIN pg_class rel ON rel.oid = con.conrelid
WHERE rel.relname = 'pengguna' AND con.contype = 'c';

-- STEP 2: Hapus constraint role lama (jika ada, nama bisa berbeda-beda)
-- Sesuaikan nama constraint dari hasil STEP 1 jika berbeda
DO $$
DECLARE
  conname text;
BEGIN
  SELECT con.conname INTO conname
  FROM pg_constraint con
  JOIN pg_class rel ON rel.oid = con.conrelid
  WHERE rel.relname = 'pengguna' AND con.contype = 'c'
    AND pg_get_constraintdef(con.oid) ILIKE '%role%';

  IF conname IS NOT NULL THEN
    EXECUTE format('ALTER TABLE public.pengguna DROP CONSTRAINT %I', conname);
    RAISE NOTICE 'Dropped constraint: %', conname;
  ELSE
    RAISE NOTICE 'Tidak ada constraint role ditemukan — lanjut aman';
  END IF;
END $$;

-- STEP 3: Pastikan kolom nip dan jabatan_resmi ada (idempotent)
ALTER TABLE public.pengguna ADD COLUMN IF NOT EXISTS nip TEXT;
ALTER TABLE public.pengguna ADD COLUMN IF NOT EXISTS jabatan_resmi TEXT;

-- STEP 4: Tambah constraint baru yang mengizinkan 'kpa'
ALTER TABLE public.pengguna ADD CONSTRAINT pengguna_role_check
  CHECK (role IN ('admin','kpa','input','view'));

-- STEP 5: Verifikasi akhir
SELECT con.conname AS constraint_name, pg_get_constraintdef(con.oid) AS definition
FROM pg_constraint con
JOIN pg_class rel ON rel.oid = con.conrelid
WHERE rel.relname = 'pengguna' AND con.contype = 'c';

SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'pengguna'
ORDER BY ordinal_position;
