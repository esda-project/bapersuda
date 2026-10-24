-- ============================================================================
-- 05_cek_kas_tahapan.sql — HANYA PEMERIKSAAN (SELECT). Tidak mengubah data apa pun.
-- Jalankan di Supabase > SQL Editor. Ganti '2026' bila perlu.
-- ============================================================================

-- 1) Jumlah baris kas per tahapan (Murni / Pergeseran / Perubahan)
select tahapan, count(*) as baris, count(distinct kode_rekening) as rekening, sum(nominal) as total_nominal
from public.kas_anggaran
where tahun = '2026' and deleted_at is null
group by tahapan order by tahapan;

-- 2) Rekening yang kas Murni-nya IDENTIK dengan Pergeseran pada semua bulan.
--    Wajar bila memang direncanakan sama. Jika seharusnya berbeda, kemungkinan Murni
--    tertimpa oleh bug lama (simpan Pergeseran ikut menimpa Murni) -> isi ulang kas Murni.
with m as (select kode_rekening, bulan, nominal from public.kas_anggaran where tahun='2026' and tahapan='Murni' and deleted_at is null),
     p as (select kode_rekening, bulan, nominal from public.kas_anggaran where tahun='2026' and tahapan like 'Pergeseran%' and deleted_at is null)
select m.kode_rekening,
       sum(m.nominal) as total_murni, sum(p.nominal) as total_pergeseran,
       bool_and(m.nominal = p.nominal) as identik_semua_bulan
from m join p using (kode_rekening, bulan)
group by m.kode_rekening
order by identik_semua_bulan desc, m.kode_rekening;

-- 3) Kas yang melebihi pagu, per tahapan (pagu kosong = ikut tahapan sebelumnya)
select k.tahapan, k.kode_rekening, sum(k.nominal) as total_kas,
       case when k.tahapan = 'Perubahan' then coalesce(a.pagu_perubahan, a.pagu_pergeseran, a.pagu_murni)
            when k.tahapan like 'Pergeseran%' then coalesce(a.pagu_pergeseran, a.pagu_murni)
            else a.pagu_murni end as pagu
from public.kas_anggaran k
join public.anggaran a on a.tahun = k.tahun and a.kode_rekening = k.kode_rekening
where k.tahun='2026' and k.deleted_at is null
group by k.tahapan, k.kode_rekening, a.pagu_murni, a.pagu_pergeseran, a.pagu_perubahan
having sum(k.nominal) >
       case when k.tahapan = 'Perubahan' then coalesce(a.pagu_perubahan, a.pagu_pergeseran, a.pagu_murni)
            when k.tahapan like 'Pergeseran%' then coalesce(a.pagu_pergeseran, a.pagu_murni)
            else a.pagu_murni end
order by k.tahapan, k.kode_rekening;

-- 4) Baris anggaran yang pagu Pergeseran/Perubahan-nya = 0 padahal pagu Murni > 0.
--    Bisa akibat bug lama form edit (kolom kosong tersimpan 0). Periksa: apakah memang dihapus
--    pada tahapan itu, atau seharusnya kosong (= ikut tahapan sebelumnya)?
select kode_rekening, nama_belanja, pagu_murni, pagu_pergeseran, pagu_perubahan
from public.anggaran
where tahun='2026' and pagu_murni > 0
  and (pagu_pergeseran = 0 or pagu_perubahan = 0)
order by kode_rekening;
-- Bila ternyata seharusnya kosong, perbaiki manual per baris, contoh:
--   update public.anggaran set pagu_pergeseran = null where id = '<id baris>';
