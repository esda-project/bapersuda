-- ============================================================================
-- KAS ANGGARAN (struktur relasional: tahun, kode_rekening, tahapan, bulan, nominal)
-- Menyiapkan tabel untuk index.html versi baru. TIDAK mengubah nominal yang ada.
-- 1) cadangan  2) rapikan baris ganda  3) batas unik untuk upsert  4) muat ulang cache
-- ============================================================================
create table if not exists public.kas_anggaran_cadangan as table public.kas_anggaran;

-- Baris ganda (rekening+tahapan+bulan sama): pertahankan yang aktif & terbaru (salinan ada di tabel cadangan)
delete from public.kas_anggaran k using (
  select ctid as c, row_number() over (
           partition by tahun, kode_rekening, tahapan, bulan
           order by (deleted_at is null) desc, updated_at desc nulls last, ctid desc) as rn
  from public.kas_anggaran) d
where k.ctid = d.c and d.rn > 1;

create unique index if not exists kas_anggaran_uniq_tahun_rek_tahapan_bulan
  on public.kas_anggaran (tahun, kode_rekening, tahapan, bulan);

notify pgrst, 'reload schema';

-- Cek: rentang bulan (1–12 atau 0–11) & jumlah baris (harus sama dengan sebelum dijalankan, kecuali ada baris ganda)
select min(bulan) as bulan_min, max(bulan) as bulan_maks, count(*) as total_baris,
       (select count(*) from public.kas_anggaran_cadangan) as baris_cadangan
from public.kas_anggaran;
