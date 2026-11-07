-- ============================================================================
-- SIANGGARAN — RIWAYAT AKTIVITAS (audit log) + fungsi pembatalan
-- ----------------------------------------------------------------------------
-- Mencatat OTOMATIS di level database: siapa, kapan, apa yang ditambah /
-- diubah / dihapus pada tabel anggaran, realisasi, dan kas_anggaran, lengkap
-- dengan data LAMA dan data BARU. Karena di database, perubahan lewat aplikasi
-- maupun SQL Editor sama-sama tercatat (SQL Editor tercatat sebagai "SQL Editor").
--
-- Sifat      : hanya MENAMBAH objek baru. Tidak mengubah data anggaran.
-- Aman diulang: ya (idempotent).
-- Jalankan   : Supabase > SQL Editor > paste seluruh file > Run.
-- Catatan    : riwayat hanya ada SEJAK skrip ini dijalankan. Untuk kejadian
--              sebelumnya gunakan perbandingan cadangan (skrip 09).
-- Rollback   : lihat BAGIAN 6 di bawah.
-- ============================================================================

-- 1. Tabel riwayat ------------------------------------------------------------
create table if not exists public.sianggaran_riwayat (
  id             bigint generated always as identity primary key,
  waktu          timestamptz not null default now(),
  tabel          text        not null,              -- anggaran | realisasi | kas_anggaran
  aksi           text        not null,              -- INSERT | UPDATE | DELETE
  baris_id       text,
  tahun          text,
  kode_rekening  text,
  user_id        uuid,
  username       text,
  nama           text,
  role           text,
  kolom_berubah  text[],                            -- khusus UPDATE
  data_lama      jsonb,
  data_baru      jsonb
);

create index if not exists sianggaran_riwayat_waktu_idx on public.sianggaran_riwayat (waktu desc);
create index if not exists sianggaran_riwayat_rek_idx   on public.sianggaran_riwayat (kode_rekening);
create index if not exists sianggaran_riwayat_baris_idx on public.sianggaran_riwayat (tabel, baris_id);

comment on table public.sianggaran_riwayat is
  'Riwayat aktivitas SIANGGARAN (diisi trigger sg_audit_trg). Tidak boleh ditulis langsung oleh klien.';

alter table public.sianggaran_riwayat enable row level security;

-- Hanya admin yang boleh MEMBACA; tidak ada kebijakan tulis untuk klien (trigger SECURITY DEFINER yang menulis).
drop policy if exists riwayat_sel_admin on public.sianggaran_riwayat;
create policy riwayat_sel_admin on public.sianggaran_riwayat
  for select to authenticated
  using ( public.sg_auth_role() = 'admin' );

revoke all on public.sianggaran_riwayat from public, anon, authenticated;
grant  select on public.sianggaran_riwayat to authenticated;

-- 2. Fungsi pencatat (trigger) -------------------------------------------------
create or replace function public.sg_audit_trg()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old  jsonb;
  v_new  jsonb;
  v_row  jsonb;
  v_cols text[];
  v_uid  uuid;
  v_user text;
  v_nama text;
  v_role text;
begin
  v_uid := (select auth.uid());
  select p.username, p.nama, p.role
    into v_user, v_nama, v_role
  from public.sianggaran_profiles p
  where p.id = v_uid;

  if tg_op in ('UPDATE', 'DELETE') then v_old := to_jsonb(old); end if;
  if tg_op in ('INSERT', 'UPDATE') then v_new := to_jsonb(new); end if;

  if tg_op = 'UPDATE' then
    select array_agg(n.k order by n.k)
      into v_cols
    from jsonb_each(v_new) as n(k, v)
    where (v_old -> n.k) is distinct from n.v;
    if v_cols is null then
      return null;                                  -- tidak ada nilai yang berubah
    end if;
  end if;

  v_row := coalesce(v_new, v_old);

  insert into public.sianggaran_riwayat
    (tabel, aksi, baris_id, tahun, kode_rekening,
     user_id, username, nama, role, kolom_berubah, data_lama, data_baru)
  values
    (tg_table_name, tg_op, v_row ->> 'id', v_row ->> 'tahun', v_row ->> 'kode_rekening',
     v_uid,
     coalesce(v_user, 'SQL Editor / sistem (' || current_user || ')'),
     v_nama, v_role, v_cols, v_old, v_new);

  return null;
end
$$;

revoke all on function public.sg_audit_trg() from public, anon, authenticated;

-- 3. Pasang trigger ------------------------------------------------------------
drop trigger if exists sg_audit_anggaran on public.anggaran;
create trigger sg_audit_anggaran
  after insert or update or delete on public.anggaran
  for each row execute function public.sg_audit_trg();

drop trigger if exists sg_audit_realisasi on public.realisasi;
create trigger sg_audit_realisasi
  after insert or update or delete on public.realisasi
  for each row execute function public.sg_audit_trg();

drop trigger if exists sg_audit_kas_anggaran on public.kas_anggaran;
create trigger sg_audit_kas_anggaran
  after insert or update or delete on public.kas_anggaran
  for each row execute function public.sg_audit_trg();

-- 4. Pembatalan satu aktivitas (khusus admin; anggaran & realisasi) ------------
--    UPDATE -> kolom yang berubah dikembalikan ke nilai LAMA
--    INSERT -> baris yang ditambahkan dihapus
--    DELETE -> baris yang dihapus dikembalikan (dari data lama)
--    Pembatalan itu sendiri juga tercatat di riwayat.
create or replace function public.sg_riwayat_batalkan(p_id bigint)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  r    public.sianggaran_riwayat%rowtype;
  col  text;
  sets text := '';
  n    int;
begin
  if coalesce(public.sg_auth_role(), '') <> 'admin' then
    raise exception 'Hanya Administrator yang boleh membatalkan aktivitas.';
  end if;

  select * into r from public.sianggaran_riwayat where id = p_id;
  if not found then
    raise exception 'Riwayat #% tidak ditemukan.', p_id;
  end if;
  if r.tabel not in ('anggaran', 'realisasi') then
    raise exception 'Pembatalan otomatis hanya untuk tabel anggaran dan realisasi.';
  end if;

  if r.aksi = 'UPDATE' then
    foreach col in array r.kolom_berubah loop
      sets := sets || format('%I = (jsonb_populate_record(null::public.%I, $1)).%I, ', col, r.tabel, col);
    end loop;
    sets := left(sets, length(sets) - 2);
    execute format('update public.%I set %s where id::text = $2', r.tabel, sets)
      using r.data_lama, r.baris_id;
    get diagnostics n = row_count;
    if n = 0 then raise exception 'Baris sudah tidak ada (mungkin sudah dihapus).'; end if;
    return 'Perubahan dibatalkan: ' || array_to_string(r.kolom_berubah, ', ') || ' dikembalikan ke nilai lama.';

  elsif r.aksi = 'INSERT' then
    execute format('delete from public.%I where id::text = $1', r.tabel) using r.baris_id;
    get diagnostics n = row_count;
    if n = 0 then raise exception 'Baris sudah tidak ada (mungkin sudah dihapus).'; end if;
    return 'Penambahan dibatalkan: baris dihapus.';

  elsif r.aksi = 'DELETE' then
    execute format('insert into public.%I select * from jsonb_populate_record(null::public.%I, $1)', r.tabel, r.tabel)
      using r.data_lama;
    return 'Penghapusan dibatalkan: baris dikembalikan.';
  end if;

  raise exception 'Aksi % tidak dikenal.', r.aksi;
end
$$;

revoke all on function public.sg_riwayat_batalkan(bigint) from public, anon;
grant  execute on function public.sg_riwayat_batalkan(bigint) to authenticated;

-- 5. Uji cepat (SELECT saja): harus menampilkan 3 trigger -----------------------
select event_object_table as tabel, trigger_name
from information_schema.triggers
where trigger_name in ('sg_audit_anggaran', 'sg_audit_realisasi', 'sg_audit_kas_anggaran')
group by 1, 2
order by 1;

-- 6. ROLLBACK (jalankan hanya bila ingin mencopot fitur riwayat) ----------------
-- drop trigger if exists sg_audit_anggaran     on public.anggaran;
-- drop trigger if exists sg_audit_realisasi    on public.realisasi;
-- drop trigger if exists sg_audit_kas_anggaran on public.kas_anggaran;
-- drop function if exists public.sg_riwayat_batalkan(bigint);
-- drop function if exists public.sg_audit_trg();
-- -- (tabel sianggaran_riwayat sengaja TIDAK di-drop agar jejak lama tetap ada)
