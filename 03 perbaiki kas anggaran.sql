-- ============================================================================
-- PERBAIKAN: "Could not find the 'data' column of 'kas_anggaran' in the schema cache"
-- Aman diulang. Tidak menghapus baris/data. Jalankan di Supabase SQL Editor.
-- Struktur yang dipakai aplikasi: id, tahun, kode_rekening, tahapan, data(jsonb)
-- ============================================================================
do $$
declare bln text[] := array['jan','feb','mar','apr','mei','jun','jul','agu','sep','okt','nov','des'];
        b text; ada_semua boolean := true; ekspresi text := '';
begin
  create table if not exists public.kas_anggaran (
    id text primary key, tahun text not null, kode_rekening text not null,
    tahapan text default 'Murni', data jsonb default '{}'::jsonb);

  alter table public.kas_anggaran add column if not exists id text;
  alter table public.kas_anggaran add column if not exists tahun text;
  alter table public.kas_anggaran add column if not exists kode_rekening text;
  alter table public.kas_anggaran add column if not exists tahapan text default 'Murni';
  alter table public.kas_anggaran add column if not exists data jsonb default '{}'::jsonb;

  -- Pengaman: struktur baris-per-bulan tidak boleh digabung otomatis (mencegah data hilang)
  if exists (select 1 from information_schema.columns where table_schema='public' and table_name='kas_anggaran'
             and column_name in ('bulan','bulan_ke','nominal','triwulan')) then
    raise exception 'kas_anggaran berstruktur baris-per-bulan. Skrip dihentikan, TIDAK ada data yang diubah. Kirim daftar kolom tabel ke pengembang.';
  end if;

  -- Jika data bulanan tersimpan di kolom terpisah (jan..des), pindahkan ke kolom data
  foreach b in array bln loop
    if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='kas_anggaran' and column_name=b) then ada_semua := false; end if;
    ekspresi := ekspresi || format('%L, coalesce(%I,0),', b, b);
  end loop;
  if ada_semua then
    execute 'update public.kas_anggaran set data = jsonb_build_object(' || rtrim(ekspresi,',') || ') where data is null or data = ''{}''::jsonb';
  end if;

  -- Aplikasi memakai id TEKS berformat tahun_kode_tahapan; ubah bila kolom id bertipe uuid
  if (select data_type from information_schema.columns where table_schema='public' and table_name='kas_anggaran' and column_name='id') <> 'text' then
    alter table public.kas_anggaran alter column id drop default;
    alter table public.kas_anggaran alter column id type text using id::text;
  end if;

  update public.kas_anggaran set tahapan = 'Murni' where tahapan is null or tahapan = '';

  -- Hapus baris ganda (tahun+rekening+tahapan sama); pertahankan yang datanya terisi
  delete from public.kas_anggaran k where k.ctid <> (
    select (array_agg(k2.ctid order by (k2.data is null or k2.data = '{}'::jsonb), k2.ctid desc))[1]
    from public.kas_anggaran k2
    where k2.tahun::text = k.tahun::text and k2.kode_rekening = k.kode_rekening and k2.tahapan = k.tahapan);

  update public.kas_anggaran
     set id = tahun::text||'_'||kode_rekening||'_'||replace(tahapan,' ','')
   where id is distinct from tahun::text||'_'||kode_rekening||'_'||replace(tahapan,' ','');

  -- Batas unik lama (tahun,kode_rekening) bentrok dengan multi-tahapan -> hapus bila ada
  perform 1 from pg_constraint where conrelid='public.kas_anggaran'::regclass and conname='kas_anggaran_tahun_kode_rekening_key';
  if found then alter table public.kas_anggaran drop constraint kas_anggaran_tahun_kode_rekening_key; end if;
end $$;

-- Dibutuhkan agar upsert (onConflict: id) berhasil
create unique index if not exists kas_anggaran_id_uidx on public.kas_anggaran (id);

-- Muat ulang cache skema API (inilah yang menghilangkan pesan "schema cache")
notify pgrst, 'reload schema';

-- Hasil: kolom harus memuat id, tahun, kode_rekening, tahapan, data
select column_name, data_type from information_schema.columns
 where table_schema='public' and table_name='kas_anggaran' order by ordinal_position;
