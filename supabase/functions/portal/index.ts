// Ideali CAD · Portal do cliente (página pública de acompanhamento).
// Não usa login: o dono do link é identificado só pelo token secreto, validado aqui
// no servidor. Devolve apenas os pedidos do cliente daquele link e links de
// arquivo assinados que valem 10 minutos. Nada de chave secreta vai para o navegador.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { AwsClient } from "npm:aws4fetch@1.0.20";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json", "Cache-Control": "no-store" } });
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const TOKEN = /^[A-Za-z0-9_-]{40,64}$/;
// O cliente só vê o caso a partir de "Aguardando aprovação" e até o cadista arquivar.
const VISIVEIS = ["aprovacao", "finalizado"];

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json(405, { erro: "Método não permitido" });
  const body = await req.json().catch(() => ({}));
  const t = String(body?.t ?? "");
  if (!TOKEN.test(t)) return json(404, { erro: "Link inválido." });

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data: link } = await admin.from("links_cliente").select("id,user_id,cliente_id")
    .eq("token", t).is("revogado_em", null).maybeSingle();
  if (!link) return json(404, { erro: "Este link foi cancelado ou não existe. Peça um novo ao seu cadista." });
  const dono = link.user_id, cid = link.cliente_id;

  if (body.acao === "listar") {
    const { data: cli } = await admin.from("clientes").select("nome,sobrenome,empresa,titulo").eq("id", cid).eq("user_id", dono).is("deleted_at", null).maybeSingle();
    if (!cli) return json(404, { erro: "Este link não está mais disponível." });
    const { data: perfil } = await admin.from("perfis").select("nome,telefone").eq("user_id", dono).maybeSingle();
    const { data: peds } = await admin.from("pedidos")
      .select("id,numero,paciente,elementos,itens,extras,tipo_trabalho_id,status,urgente,recebido_em,prazo,enviado_em,pago_em,valor,pendencia_motivos,pendencia_obs,aprovacao_desde,ajustes,material,fresadora,scanbody_img")
      .eq("user_id", dono).eq("cliente_id", cid).is("deleted_at", null)
      .in("status", VISIVEIS)
      .order("numero", { ascending: false }).limit(300);
    // deno-lint-ignore no-explicit-any
    const lista = (peds ?? []) as any[];
    // Print do scanbody: URL assinada (1 hora) do bucket privado "pedido-img", só da pasta do dono.
    for (const p of lista) {
      const path = String(p.scanbody_img ?? "");
      delete p.scanbody_img;
      if (path && path.startsWith(dono + "/")) {
        const { data: su } = await admin.storage.from("pedido-img").createSignedUrl(path, 3600);
        if (su?.signedUrl) p.scanbody_url = su.signedUrl;
      }
    }
    const tipoIds = new Set<string>();
    for (const p of lista) {
      if (p.tipo_trabalho_id) tipoIds.add(p.tipo_trabalho_id);
      for (const i of (p.itens ?? [])) if (i?.t) tipoIds.add(String(i.t));
      for (const x of (p.extras ?? [])) if (x?.t) tipoIds.add(String(x.t));
    }
    const ids = [...tipoIds].filter((x) => UUID.test(x));
    const { data: tipos } = ids.length ? await admin.from("tipos_trabalho").select("id,nome").eq("user_id", dono).in("id", ids) : { data: [] };
    const pids = lista.map((p) => p.id);
    const { data: arqs } = pids.length ? await admin.from("arquivos").select("id,pedido_id,origem,nome,url_externa,tamanho_zip,criado_em,categoria")
      .eq("user_id", dono).in("pedido_id", pids).is("deleted_at", null).is("removido_em", null) : { data: [] };
    await admin.from("links_cliente").update({ ultimo_acesso: new Date().toISOString() }).eq("id", link.id);
    const nomeCli = (cli.empresa || "").trim() || [cli.titulo, cli.nome, cli.sobrenome].filter(Boolean).join(" ");
    return json(200, { cliente: nomeCli, cadista: perfil?.nome ?? "", telefone: perfil?.telefone ?? "", pedidos: lista, tipos: tipos ?? [], arquivos: arqs ?? [] });
  }

  if (body.acao === "baixar") {
    const id = String(body.arquivo_id ?? "");
    if (!UUID.test(id)) return json(400, { erro: "Arquivo inválido." });
    const { data: a } = await admin.from("arquivos").select("nome,storage_key,pedido_id,origem")
      .eq("id", id).eq("user_id", dono).is("deleted_at", null).is("removido_em", null).maybeSingle();
    if (!a || a.origem !== "upload" || !a.storage_key) return json(404, { erro: "Arquivo não encontrado." });
    const { data: ped } = await admin.from("pedidos").select("id").eq("id", a.pedido_id).eq("user_id", dono).eq("cliente_id", cid).is("deleted_at", null).in("status", VISIVEIS).maybeSingle();
    if (!ped) return json(404, { erro: "Arquivo não encontrado." });
    const acc = Deno.env.get("R2_ACCOUNT_ID"), kid = Deno.env.get("R2_ACCESS_KEY_ID");
    const sec = Deno.env.get("R2_SECRET_ACCESS_KEY"), bucket = Deno.env.get("R2_BUCKET");
    if (!acc || !kid || !sec || !bucket) return json(503, { erro: "O armazenamento de arquivos ainda não foi configurado." });
    const r2 = new AwsClient({ accessKeyId: kid, secretAccessKey: sec, service: "s3", region: "auto" });
    const u = new URL(`https://${acc}.r2.cloudflarestorage.com/${bucket}/${a.storage_key.split("/").map(encodeURIComponent).join("/")}`);
    u.searchParams.set("X-Amz-Expires", "600");
    const url = (await r2.sign(new Request(u, { method: "GET" }), { aws: { signQuery: true } })).url;
    return json(200, { url, nome: a.nome });
  }

  return json(400, { erro: "Ação desconhecida." });
});
