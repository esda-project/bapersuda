// SIANGGARAN — Edge Function: admin-users
// Mengelola akun (Supabase Auth + tabel public.profiles) HANYA untuk pemanggil ber-role admin.
// service_role key tidak pernah keluar dari fungsi ini (dibaca dari environment Edge Function).
//
// Aksi (body JSON { action, ... }):
//   create        { username, nama, role, jabatan?, nip?, jabatan_resmi?, pptk_nama?, password }
//   update        { id, nama?, role?, jabatan?, nip?, jabatan_resmi?, pptk_nama?, password? }
//   delete        { id }
//   import_legacy {}   -> membuat akun dari tabel lama `pengguna` dengan password sementara acak
//
// Deploy: supabase functions deploy admin-users   (verify_jwt aktif — jangan dimatikan)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

// HARUS sama dengan AUTH_EMAIL_DOMAIN di index.html dan 00_bootstrap_admin.sql
const EMAIL_DOMAIN = "sianggaran.invalid";
const ROLES = ["admin", "kpa", "input", "view"];
const USERNAME_RE = /^[a-z0-9._-]{3,40}$/;
const MIN_PASSWORD = 12;

const CORS = {
  "Access-Control-Allow-Origin": "*", // dilindungi JWT Bearer; tidak memakai cookie
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });

const fail = (status: number, message: string) => json({ error: message }, status);

const str = (v: unknown, max = 200) =>
  typeof v === "string" ? v.trim().slice(0, max) : "";

function tempPassword(len = 14): string {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789";
  const buf = new Uint32Array(len);
  crypto.getRandomValues(buf);
  return Array.from(buf, (n) => chars[n % chars.length]).join("");
}

const normNama = (s: string) => s.trim().replace(/\s+/g, " ").toUpperCase();

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return fail(405, "Metode tidak diizinkan");

  const url = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  // 1. Autentikasi pemanggil dari JWT-nya
  const authHeader = req.headers.get("Authorization") ?? "";
  const caller = createClient(url, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: u, error: uErr } = await caller.auth.getUser();
  if (uErr || !u?.user) return fail(401, "Sesi tidak valid. Silakan login ulang.");

  // 2. Otorisasi: pemanggil WAJIB admin menurut tabel profiles (bukan klaim dari klien)
  const admin = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: me } = await admin
    .from("profiles").select("id, role").eq("id", u.user.id).maybeSingle();
  if (!me || me.role !== "admin") return fail(403, "Hanya admin yang boleh mengelola pengguna.");

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return fail(400, "Body JSON tidak valid."); }
  const action = str(body.action, 30);

  const countAdmins = async () => {
    const { count } = await admin.from("profiles")
      .select("id", { count: "exact", head: true }).eq("role", "admin");
    return count ?? 0;
  };

  try {
    // ------------------------------------------------------------------ create
    if (action === "create") {
      const username = str(body.username, 40).toLowerCase();
      const nama = str(body.nama);
      const role = str(body.role, 10);
      const password = typeof body.password === "string" ? body.password : "";
      if (!USERNAME_RE.test(username)) return fail(400, "Username 3–40 karakter: huruf kecil, angka, titik, strip, garis bawah.");
      if (!nama) return fail(400, "Nama wajib diisi.");
      if (!ROLES.includes(role)) return fail(400, "Role tidak valid.");
      if (password.length < MIN_PASSWORD) return fail(400, `Password minimal ${MIN_PASSWORD} karakter.`);

      const { data: exists } = await admin.from("profiles").select("id").eq("username", username).maybeSingle();
      if (exists) return fail(409, "Username sudah digunakan.");

      const { data: created, error: cErr } = await admin.auth.admin.createUser({
        email: `${username}@${EMAIL_DOMAIN}`, password, email_confirm: true,
      });
      if (cErr || !created?.user) { console.error("createUser", cErr?.message); return fail(400, "Gagal membuat akun."); }

      const { error: pErr } = await admin.from("profiles").insert({
        id: created.user.id, username, nama, role,
        jabatan: str(body.jabatan) || null, nip: str(body.nip, 30) || null,
        jabatan_resmi: str(body.jabatan_resmi) || null,
        pptk_nama: role === "input" ? (str(body.pptk_nama) || null) : null,
        must_change_password: true,
      });
      if (pErr) {
        console.error("insert profile", pErr.message);
        await admin.auth.admin.deleteUser(created.user.id); // batalkan agar tidak ada akun yatim
        return fail(400, "Gagal menyimpan profil pengguna.");
      }
      return json({ ok: true, id: created.user.id });
    }

    // ------------------------------------------------------------------ update
    if (action === "update") {
      const id = str(body.id, 60);
      const { data: target } = await admin.from("profiles").select("id, role").eq("id", id).maybeSingle();
      if (!target) return fail(404, "Pengguna tidak ditemukan.");

      const patch: Record<string, unknown> = {};
      if (body.nama !== undefined) { const n = str(body.nama); if (!n) return fail(400, "Nama wajib diisi."); patch.nama = n; }
      if (body.jabatan !== undefined) patch.jabatan = str(body.jabatan) || null;
      if (body.nip !== undefined) patch.nip = str(body.nip, 30) || null;
      if (body.jabatan_resmi !== undefined) patch.jabatan_resmi = str(body.jabatan_resmi) || null;
      const newRole = body.role !== undefined ? str(body.role, 10) : target.role;
      if (!ROLES.includes(newRole)) return fail(400, "Role tidak valid.");
      if (body.role !== undefined) patch.role = newRole;
      if (body.pptk_nama !== undefined || body.role !== undefined) {
        patch.pptk_nama = newRole === "input" ? (str(body.pptk_nama) || null) : null;
      }
      // Cegah kehilangan admin terakhir / admin menurunkan dirinya sendiri
      if (target.role === "admin" && newRole !== "admin") {
        if (id === me.id) return fail(400, "Anda tidak dapat menurunkan role akun Anda sendiri.");
        if ((await countAdmins()) <= 1) return fail(400, "Harus tersisa minimal satu admin.");
      }

      const password = typeof body.password === "string" ? body.password : "";
      if (password) {
        if (password.length < MIN_PASSWORD) return fail(400, `Password minimal ${MIN_PASSWORD} karakter.`);
        const { error: pwErr } = await admin.auth.admin.updateUserById(id, { password });
        if (pwErr) { console.error("updateUser", pwErr.message); return fail(400, "Gagal mengubah password."); }
        if (id !== me.id) patch.must_change_password = true;
      }
      if (Object.keys(patch).length) {
        const { error } = await admin.from("profiles").update(patch).eq("id", id);
        if (error) { console.error("update profile", error.message); return fail(400, "Gagal menyimpan perubahan."); }
      }
      return json({ ok: true });
    }

    // ------------------------------------------------------------------ delete
    if (action === "delete") {
      const id = str(body.id, 60);
      if (id === me.id) return fail(400, "Anda tidak dapat menghapus akun Anda sendiri.");
      const { data: target } = await admin.from("profiles").select("id, role").eq("id", id).maybeSingle();
      if (!target) return fail(404, "Pengguna tidak ditemukan.");
      if (target.role === "admin" && (await countAdmins()) <= 1) return fail(400, "Harus tersisa minimal satu admin.");
      const { error } = await admin.auth.admin.deleteUser(id); // profiles ikut terhapus (ON DELETE CASCADE)
      if (error) { console.error("deleteUser", error.message); return fail(400, "Gagal menghapus akun."); }
      return json({ ok: true });
    }

    // ----------------------------------------------------------- import_legacy
    if (action === "import_legacy") {
      const { data: legacy, error: lErr } = await admin.from("pengguna").select("*");
      if (lErr) { console.error("legacy", lErr.message); return fail(400, "Tabel pengguna lama tidak dapat dibaca."); }

      const report: Array<Record<string, string>> = [];
      for (const row of legacy ?? []) {
        const username = str(row.username, 60).toLowerCase();
        const nama = str(row.nama);
        const role = ROLES.includes(row.role) ? row.role : "view";
        if (!USERNAME_RE.test(username) || !nama) {
          report.push({ username: String(row.username ?? ""), status: "DILEWATI: username/nama tidak valid" });
          continue;
        }
        const { data: exists } = await admin.from("profiles").select("id").eq("username", username).maybeSingle();
        if (exists) { report.push({ username, status: "DILEWATI: sudah ada" }); continue; }

        const password = tempPassword();
        const { data: created, error: cErr } = await admin.auth.admin.createUser({
          email: `${username}@${EMAIL_DOMAIN}`, password, email_confirm: true,
        });
        if (cErr || !created?.user) { console.error("legacy create", username, cErr?.message); report.push({ username, status: "GAGAL membuat akun" }); continue; }

        // Perilaku lama: akun ber-username "pptk*" dibatasi ke nama PPTK-nya. Akun lain tidak dibatasi.
        const scoped = role === "input" && username.startsWith("pptk");
        const { error: pErr } = await admin.from("profiles").insert({
          id: created.user.id, username, nama, role,
          jabatan: row.jabatan ?? null, nip: row.nip ?? null, jabatan_resmi: row.jabatan_resmi ?? null,
          pptk_nama: scoped ? normNama(nama) : null,
          must_change_password: true,
        });
        if (pErr) {
          console.error("legacy profile", username, pErr.message);
          await admin.auth.admin.deleteUser(created.user.id);
          report.push({ username, status: "GAGAL menyimpan profil" });
          continue;
        }
        report.push({ username, nama, role, temp_password: password, status: "DIBUAT" });
      }
      // Password sementara dikembalikan SEKALI ke admin; tidak disimpan & tidak di-log.
      return json({ ok: true, report });
    }

    return fail(400, "Aksi tidak dikenal.");
  } catch (e) {
    console.error("admin-users", (e as Error).message);
    return fail(500, "Terjadi kesalahan pada server.");
  }
});
