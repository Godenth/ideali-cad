// Ideali CAD · Página de captura dos anúncios (pública, sem login).
// "info": devolve o primeiro nome do cadista e o título da página pelo apelido (slug).
// "enviar": grava o contato na lista do dono (captura_leads) e devolve o número do WhatsApp do cadista
// para o visitante ser levado à conversa. Limites: 5 envios por IP por hora e 300 por página por dia.
// Nada de chave secreta vai para o navegador; o IP é guardado só como hash.
import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json", "Cache-Control": "no-store" } });
const SLUG = /^[a-z0-9][a-z0-9-]{2,39}$/;
const limpa = (v: unknown, n: number) => String(v ?? "").replace(/[\u0000-\u001f<>]/g, " ").replace(/\s+/g, " ").trim().slice(0, n);
const soDig = (v: unknown) => String(v ?? "").replace(/\D/g, "");
function telNorm(v: unknown) {
  let d = soDig(v);
  if (d.length >= 12 && d.startsWith("55")) d = d.slice(2);
  return d.length >= 10 && d.length <= 11 ? d : "";
}
async function hash(s: string) {
  const b = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s + (Deno.env.get("SUPABASE_URL") ?? "")));
  return [...new Uint8Array(b)].slice(0, 12).map((x) => x.toString(16).padStart(2, "0")).join("");
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json(405, { erro: "Método não permitido" });
  const body = await req.json().catch(() => ({}));
  const slug = String(body?.u ?? "").toLowerCase();
  if (!SLUG.test(slug)) return json(404, { erro: "Página não encontrada." });
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data: pg } = await admin.from("captura_paginas").select("user_id,ativo,titulo,msg,wa,pixel").eq("slug", slug).maybeSingle();
  if (!pg || !pg.ativo) return json(404, { erro: "Esta página não está disponível." });
  const { data: perfil } = await admin.from("perfis").select("nome,telefone,cidade,uf").eq("user_id", pg.user_id).maybeSingle();
  const tel = telNorm(pg.wa) || telNorm(perfil?.telefone); // número próprio da página, se houver
  const nome = limpa(perfil?.nome, 60);
  const primeiro = nome.split(" ")[0] || "";

  if (body.acao === "info") {
    return json(200, { nome: primeiro, nomeCompleto: nome, titulo: pg.titulo ?? "", cidade: [perfil?.cidade, perfil?.uf].filter(Boolean).join("/"), temWhats: !!tel, pixel: pg.pixel ?? "" });
  }

  if (body.acao === "enviar") {
    if (String(body.site ?? "") !== "") return json(200, { ok: true, wa: tel ? "55" + tel : "" }); // armadilha para robôs
    const n = limpa(body.nome, 60), t = telNorm(body.tel);
    const tipo = ["dentista", "protetico", "outro"].includes(String(body.tipo)) ? String(body.tipo) : "outro";
    if (n.length < 2) return json(400, { erro: "Digite o seu nome." });
    if (!t) return json(400, { erro: "Digite o seu WhatsApp com DDD." });
    if (!body.aceite) return json(400, { erro: "Marque a autorização para o contato pelo WhatsApp." });
    const ip = (req.headers.get("x-forwarded-for") ?? "").split(",")[0].trim() || "sem-ip";
    const ih = await hash(ip);
    const umaHora = new Date(Date.now() - 3600e3).toISOString(), umDia = new Date(Date.now() - 86400e3).toISOString();
    const { count: porIp } = await admin.from("captura_leads").select("id", { count: "exact", head: true }).eq("ip_hash", ih).gte("criado_em", umaHora);
    if ((porIp ?? 0) >= 5) return json(429, { erro: "Muitos envios seguidos. Tente de novo mais tarde." });
    const { count: porDia } = await admin.from("captura_leads").select("id", { count: "exact", head: true }).eq("user_id", pg.user_id).gte("criado_em", umDia);
    if ((porDia ?? 0) >= 300) return json(429, { erro: "Tente de novo mais tarde." });
    const { data: ja } = await admin.from("captura_leads").select("id").eq("user_id", pg.user_id).eq("telefone", t).gte("criado_em", umDia).maybeSingle();
    if (!ja) {
      const { error } = await admin.from("captura_leads").insert({
        user_id: pg.user_id, nome: n, tipo, telefone: t, cidade: limpa(body.cidade, 60) || null,
        origem: limpa(body.origem, 40) || null, ip_hash: ih,
      });
      if (error) return json(500, { erro: "Não foi possível enviar agora. Tente de novo." });
    }
    return json(200, { ok: true, wa: tel ? "55" + tel : "", nome: primeiro, msg: pg.msg ?? "" });
  }
  return json(400, { erro: "Ação desconhecida." });
});
