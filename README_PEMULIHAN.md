# SIANGGARAN — Pemulihan Login (urutan wajib)

**Penyebab tidak bisa masuk:** index.html memakai Supabase Auth + tabel `sianggaran_profiles`, tetapi skrip SQL lama memakai tabel `profiles` dan akun Auth belum pernah dibuat. Data anggaran tidak berubah/hilang.

1. Supabase > SQL Editor: jalankan `01_tambahan_aman.sql` (membuat `sianggaran_profiles`, fungsi `sg_*`, kebijakan RLS untuk pengguna login).
2. Jalankan `00_bootstrap_admin.sql` → membuat akun Auth dari tabel `pengguna` lama. Hasil akhir menampilkan daftar akun.
3. Deploy `index.html` ke Vercel (commit ke GitHub). Login memakai **username + password LAMA**; sistem langsung meminta ganti password (min. 12 karakter).
4. (Menu Pengguna: tambah/ubah akun) deploy `supabase/functions/admin-users/index.ts`: `supabase functions deploy admin-users`.
5. Setelah SEMUA peran (admin, kpa, input, view) berhasil login & data tampil: jalankan `02_kunci_akses_anon.sql` (mengunci akses anonim). Darurat: `99_rollback.sql`.
