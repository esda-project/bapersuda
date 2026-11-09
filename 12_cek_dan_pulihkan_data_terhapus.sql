-- ============================================================================
-- SIANGGARAN — 12 CEK & (OPSIONAL) PULIHKAN DATA YANG TERTANDAI TERHAPUS
-- ----------------------------------------------------------------------------
-- Latar  : Database memakai trigger hapus-lunak (c_softdel -> trg_soft_delete):
--          "hapus" hanya mengisi kolom deleted_at, barisnya tetap ada.
--          index.html terbaru sudah menyaring baris ber-deleted_at, sehingga
--          data yang dihapus tidak muncul lagi setelah login ulang.
-- File ini: BAGIAN 1 hanya membaca. BAGIAN 2 (pemulihan) sengaja dikomentari;
--          pakai HANYA bila ada baris yang dihapus tidak sengaja.
-- Data    : tidak ada yang diubah selama BAGIAN 2 tidak dijalankan.
-- ============================================================================

-- BAGIAN 1 — Daftar realisasi yang tertandai terhapus ------------------------
select id, tahun, tanggal, kode_rekening, uraian, pptk, deleted_at
from public.realisasi
where deleted_at is not null
order by deleted_at desc;

-- Ringkasan per tahun: aktif vs tertandai terhapus
select tahun,
       count(*) filter (where deleted_at is null)     as aktif,
       count(*) filter (where deleted_at is not null) as tertandai_hapus
from public.realisasi
group by tahun
order by tahun;

-- BAGIAN 2 — PEMULIHAN (opsional). Hapus tanda "--" lalu isi id yang ingin dipulihkan.
-- update public.realisasi
--    set deleted_at = null
--  where id in ('ISI-ID-DI-SINI');
