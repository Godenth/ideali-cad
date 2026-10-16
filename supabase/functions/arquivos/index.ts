// Ideali CAD · Arquivos do pedido (escaneamentos e projetos, sempre em .zip) no Cloudflare R2.
// O navegador nunca vê as chaves do R2: este servidor confere o login, o dono do pedido,
// a assinatura e o espaço livre, e devolve um link assinado que vale por pouco tempo.
// Ações: "preparar" (link para enviar), "confirmar" (registra o arquivo já enviado),
// "baixar" (link para baixar ou abrir no visualizador).
import { createClient } from "jsr:@supabase/supabase-js@2";
import { AwsClient } from "npm:aws4fetch@1.0.20";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

const MAX_ARQUIVO = 2 * 1024 ** 3; // 2 GB por arquivo
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const limpaNome = (n: unknown) =>
  String(n ?? "arquivo.zip").replace(/[\\/:*?"<>|\u0000-\u001f]/g, "_").trim().slice(0, 150) || "arquivo.zip";

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json(405, { erro: "Método não permitido" });

  const acc = Deno.env.get("R2_ACCOUNT_ID"), kid = Deno.env.get("R2_ACCESS_KEY_ID");
  const sec = Deno.env.get("R2_SECRET_ACCESS_KEY"), bucket = Deno.env.get("R2_BUCKET");
  if (!acc || !kid || !sec || !bucket) return json(503, { erro: "O armazenamento de arquivos ainda não foi configurado." });

  const url = Deno.env.get("SUPABASE_URL")!;
  const auth = req.headers.get("Authorization") ?? "";
  const userClient = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, { global: { headers: { Authorization: auth } } });
  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data: { user }, error: eu } = await userClient.auth.getUser();
  if (eu || !user) return json(401, { erro: "Não autenticado" });

  const r2 = new AwsClient({ accessKeyId: kid, secretAccessKey: sec, service: "s3", region: "auto" });
  const base = `https://${acc}.r2.cloudflarestorage.com/${bucket}`;
  const objUrl = (key: string) => `${base}/${key.split("/").map(encodeURIComponent).join("/")}`;
  const assinar = async (method: string, key: string, segundos: number, extra?: Record<string, string>) => {
    const u = new URL(objUrl(key));
    u.searchParams.set("X-Amz-Expires", String(segundos));
    for (const [k, v] of Object.entries(extra ?? {})) u.searchParams.set(k, v);
    return (await r2.sign(new Request(u, { method }), { aws: { signQuery: true } })).url;
  };

  const body = await req.json().catch(() => ({}));
  const acao = body?.acao;

  // Confere que o pedido é do usuário (a regra de acesso do banco só deixa ver os próprios).
  const pedidoDoUsuario = async (pid: unknown) => {
    if (typeof pid !== "string" || !UUID.test(pid)) return false;
    const { data } = await userClient.from("pedidos").select("id").eq("id", pid).is("deleted_at", null).maybeSingle();
    return !!data;
  };
  const podeGravar = async () => {
    const { data } = await userClient.rpc("pode_arquivar");
    return data === true;
  };
  const espaco = async () => {
    const { data } = await admin.from("assinaturas").select("limite_bytes,bytes_usados").eq("user_id", user.id).maybeSingle();
    return { limite: Number(data?.limite_bytes ?? 0), usado: Number(data?.bytes_usados ?? 0) };
  };

  if (acao === "preparar") {
    const tamanho = Number(body.tamanho);
    if (!Number.isFinite(tamanho) || tamanho <= 0) return json(400, { erro: "Tamanho inválido" });
    if (tamanho > MAX_ARQUIVO) return json(413, { erro: "Arquivo maior que 2 GB. Use um link externo." });
    if (!(await pedidoDoUsuario(body.pedido_id))) return json(404, { erro: "Pedido não encontrado" });
    if (!(await podeGravar())) return json(403, { erro: "No plano grátis não é possível guardar arquivos. Assine para enviar." });
    const e = await espaco();
    if (e.usado + tamanho > e.limite) return json(413, { erro: "Sem espaço livre para este arquivo." });
    const key = `${user.id}/${body.pedido_id}/${crypto.randomUUID()}.zip`;
    return json(200, { key, url: await assinar("PUT", key, 3600) });
  }

  if (acao === "confirmar") {
    const key = String(body.key ?? "");
    const pid = String(body.pedido_id ?? "");
    if (!key.startsWith(`${user.id}/${pid}/`) || !/^[0-9a-f-]+\/[0-9a-f-]+\/[0-9a-f-]+\.zip$/i.test(key)) return json(400, { erro: "Chave inválida" });
    if (!(await pedidoDoUsuario(pid))) return json(404, { erro: "Pedido não encontrado" });
    const { data: ja } = await admin.from("arquivos").select("id").eq("storage_key", key).maybeSingle();
    if (ja) return json(409, { erro: "Arquivo já registrado" });
    const head = await r2.fetch(objUrl(key), { method: "HEAD" });
    if (!head.ok) return json(400, { erro: "O arquivo não chegou ao armazenamento. Tente enviar de novo." });
    const tamanho = Number(head.headers.get("content-length") ?? 0);
    const apaga = () => r2.fetch(objUrl(key), { method: "DELETE" });
    if (!(await podeGravar())) { await apaga(); return json(403, { erro: "No plano grátis não é possível guardar arquivos. Assine para enviar." }); }
    const e = await espaco();
    if (tamanho > MAX_ARQUIVO || e.usado + tamanho > e.limite) { await apaga(); return json(413, { erro: "Sem espaço livre para este arquivo." }); }
    const orig = Number(body.tamanho_original);
    const { data, error } = await admin.from("arquivos").insert({
      user_id: user.id, pedido_id: pid, origem: "upload", nome: limpaNome(body.nome), storage_key: key,
      tamanho_zip: tamanho, tamanho_original: Number.isFinite(orig) && orig >= 0 ? Math.round(orig) : null,
      categoria: ["scan", "html", "fres"].includes(String(body.categoria)) ? String(body.categoria) : null,
    }).select("id,pedido_id,origem,nome,tamanho_original,tamanho_zip,criado_em,categoria").single();
    if (error) { await apaga(); return json(500, { erro: "Não foi possível registrar o arquivo." }); }
    return json(200, data);
  }

  if (acao === "baixar") {
    const id = String(body.arquivo_id ?? "");
    if (!UUID.test(id)) return json(400, { erro: "Arquivo inválido" });
    const { data } = await userClient.from("arquivos").select("nome,storage_key,origem,removido_em").eq("id", id).maybeSingle();
    if (!data || data.origem !== "upload" || !data.storage_key) return json(404, { erro: "Arquivo não encontrado" });
    if (data.removido_em) return json(410, { erro: "Este arquivo já foi apagado pela limpeza automática." });
    const extra = body.salvar ? { "response-content-disposition": `attachment; filename="${limpaNome(data.nome).replace(/"/g, "")}"` } : undefined;
    return json(200, { url: await assinar("GET", data.storage_key, 600, extra) });
  }

  return json(400, { erro: "Ação desconhecida" });
});
