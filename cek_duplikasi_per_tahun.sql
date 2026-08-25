-- ============================================================
-- SIANGGARAN — Verifikasi lanjutan duplikasi kode_rekening
-- (mempertimbangkan kolom tahun — satu kode_rekening yang sama
--  untuk tahun anggaran berbeda itu WAJAR, bukan duplikasi)
-- ============================================================

-- 5a. Duplikasi kode_rekening DALAM TAHUN YANG SAMA (ini yang perlu dibersihkan)
SELECT tahun, kode_rekening, COUNT(*) AS jumlah_baris
FROM public.anggaran
GROUP BY tahun, kode_rekening
HAVING COUNT(*) > 1
ORDER BY tahun, jumlah_baris DESC;

-- 5b. Detail lengkap tiap baris untuk kode_rekening yang duplikat DALAM SATU TAHUN,
-- supaya kelihatan apakah datanya beda (pagu beda, pptk beda -> mungkin salah input)
-- atau benar-benar sama persis (double input yang perlu dihapus salah satunya)
SELECT a.*
FROM public.anggaran a
JOIN (
  SELECT tahun, kode_rekening
  FROM public.anggaran
  GROUP BY tahun, kode_rekening
  HAVING COUNT(*) > 1
) dup ON dup.tahun = a.tahun AND dup.kode_rekening = a.kode_rekening
ORDER BY a.kode_rekening, a.tahun, a.created_at;

-- 5c. Kalau ingin lihat khusus 1 kode_rekening tertentu untuk cek manual, ganti nilainya:
-- SELECT * FROM public.anggaran
-- WHERE kode_rekening = '4.01.03.2.04.0003.5.1.02.01.001.00052.PAD'
-- ORDER BY tahun, created_at;
