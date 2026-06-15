-- ============================================================
-- SCRIPT 2 dari 4: AKTIFKAN RLS + BUAT POLICY
-- Jalankan setelah Script 1 berhasil
-- ============================================================

-- Aktifkan RLS
ALTER TABLE public.pengguna     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.anggaran     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.realisasi    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.kas_anggaran ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;

-- Bersihkan policy lama yang konflik
DROP POLICY IF EXISTS pengguna_admin_all  ON public.pengguna;
DROP POLICY IF EXISTS pengguna_self_read  ON public.pengguna;
DROP POLICY IF EXISTS pengguna_anon_all   ON public.pengguna;

DROP POLICY IF EXISTS anggaran_read   ON public.anggaran;
DROP POLICY IF EXISTS anggaran_write  ON public.anggaran;
DROP POLICY IF EXISTS anggaran_anon   ON public.anggaran;

DROP POLICY IF EXISTS realisasi_read   ON public.realisasi;
DROP POLICY IF EXISTS realisasi_write  ON public.realisasi;
DROP POLICY IF EXISTS realisasi_anon   ON public.realisasi;

DROP POLICY IF EXISTS kas_anggaran_anon ON public.kas_anggaran;
DROP POLICY IF EXISTS app_settings_anon ON public.app_settings;

-- Buat policy baru (anon key = full access, kontrol akses di frontend)
CREATE POLICY pengguna_anon_all    ON public.pengguna
  FOR ALL TO anon USING (true) WITH CHECK (true);

CREATE POLICY anggaran_anon        ON public.anggaran
  FOR ALL TO anon USING (true) WITH CHECK (true);

CREATE POLICY realisasi_anon       ON public.realisasi
  FOR ALL TO anon USING (true) WITH CHECK (true);

CREATE POLICY kas_anggaran_anon    ON public.kas_anggaran
  FOR ALL TO anon USING (true) WITH CHECK (true);

CREATE POLICY app_settings_anon    ON public.app_settings
  FOR ALL TO anon USING (true) WITH CHECK (true);

-- Nota dinas (jika sudah ada dari migration kemarin)
ALTER TABLE IF EXISTS public.nota_dinas_pptk ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.nota_dinas_ppk  ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS nota_pptk_anon ON public.nota_dinas_pptk;
DROP POLICY IF EXISTS nota_ppk_anon  ON public.nota_dinas_ppk;

CREATE POLICY nota_pptk_anon ON public.nota_dinas_pptk
  FOR ALL TO anon USING (true) WITH CHECK (true);

CREATE POLICY nota_ppk_anon ON public.nota_dinas_ppk
  FOR ALL TO anon USING (true) WITH CHECK (true);

-- Verifikasi: semua tabel harus rowsecurity = true
SELECT tablename, rowsecurity
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY tablename;
