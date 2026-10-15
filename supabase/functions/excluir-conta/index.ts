// Ideali CAD · Exclui a conta do usuário logado e todos os dados dele (LGPD).
// Roda no servidor: a chave service_role nunca vai para o navegador.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { AwsClient } from "npm:aws4fetch@1.0.20";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json(405, { erro: "Método não permitido" });

  const url = Deno.env.get("SUPABASE_URL")!;
  const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  // Quem está pedindo? Confere o login com o próprio token do usuário.
  const auth = req.headers.get("Authorization") ?? "";
  const userClient = createClient(url, anon, { global: { headers: { Authorization: auth } } });
  const { data: { user }, error } = await userClient.auth.getUser();
  if (error || !user) return json(401, { erro: "Não autenticado" });

  const body = await req.json().catch(() => ({}));
  if (body?.confirmacao !== "EXCLUIR") return json(400, { erro: "Confirmação ausente" });

  const admin = createClient(url, service);

  // Apaga os arquivos do usuário no Cloudflare R2 antes de apagar a conta (LGPD).
  const acc = Deno.env.get("R2_ACCOUNT_ID"), kid = Deno.env.get("R2_ACCESS_KEY_ID");
  const sec = Deno.env.get("R2_SECRET_ACCESS_KEY"), bucket = Deno.env.get("R2_BUCKET");
  const { data: arqs } = await admin.from("arquivos").select("storage_key").eq("user_id", user.id).not("storage_key", "is", null);
  if (arqs && arqs.length) {
    if (!acc || !kid || !sec || !bucket) return json(503, { erro: "Não foi possível apagar seus arquivos agora. Tente de novo mais tarde." });
    const r2 = new AwsClient({ accessKeyId: kid, secretAccessKey: sec, service: "s3", region: "auto" });
    for (const a of arqs) {
      const key = String(a.storage_key);
      if (!key.startsWith(user.id + "/")) continue; // só a pasta do próprio usuário
      const u = `https://${acc}.r2.cloudflarestorage.com/${bucket}/${key.split("/").map(encodeURIComponent).join("/")}`;
      const r = await r2.fetch(u, { method: "DELETE" });
      if (!r.ok && r.status !== 404) return json(502, { erro: "Não foi possível apagar seus arquivos agora. Tente de novo mais tarde." });
    }
  }

  const { error: e2 } = await admin.auth.admin.deleteUser(user.id);
  if (e2) return json(500, { erro: "Não foi possível excluir a conta" });

  // Todas as tabelas têm "on delete cascade" a partir do usuário: os dados somem junto.
  return json(200, { ok: true });
});
