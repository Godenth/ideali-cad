// Ideali CAD · Arquivos do pedido (escaneamentos e projetos, sempre em .zip) no Cloudflare R2.
// O navegador nunca vê as chaves do R2: este servidor confere o login, o dono do pedido,
// a assinatura e o espaço livre, e devolve um link assinado que vale por pouco tempo.
// Ações: "preparar" (link para enviar), "confirmar" (registra o arquivo já enviado),
// "baixar" (link para baixar ou abrir no visualizador), "verificar" (confere STL/HTML dentro do zip).
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


// ---- Conferência do conteúdo do .zip (sem baixar o arquivo inteiro) ----
// Lê o índice do zip no fim do arquivo e o começo de cada STL/HTML, e confere se é mesmo uma malha STL
// (binária: 84 + 50 × triângulos bytes; texto: "solid … facet normal") e um HTML de verdade.
type Entrada = { nome: string; metodo: number; comp: number; tam: number; off: number };
async function confereZip(r2: AwsClient, url: string, total: number) {
  const faixa = async (ini: number, fim: number) => {
    const r = await r2.fetch(url, { headers: { Range: `bytes=${ini}-${fim}` } });
    if (!r.ok) throw new Error("range " + r.status);
    return new Uint8Array(await r.arrayBuffer());
  };
  const n = Math.min(total, 66000), cauda = await faixa(total - n, total - 1), dv = new DataView(cauda.buffer);
  let eocd = -1;
  for (let i = cauda.length - 22; i >= 0; i--) if (dv.getUint32(i, true) === 0x06054b50) { eocd = i; break; }
  if (eocd < 0) return { ok: false, motivo: "não é zip" };
  const qtd = dv.getUint16(eocd + 10, true), cdTam = dv.getUint32(eocd + 12, true), cdOff = dv.getUint32(eocd + 16, true);
  const cd = cdOff >= total - n ? cauda.subarray(cdOff - (total - n), cdOff - (total - n) + cdTam) : await faixa(cdOff, cdOff + cdTam - 1);
  const cv = new DataView(cd.buffer, cd.byteOffset, cd.byteLength), dec = new TextDecoder();
  const ents: Entrada[] = [];
  for (let p = 0, k = 0; k < qtd && p + 46 <= cd.length; k++) {
    if (cv.getUint32(p, true) !== 0x02014b50) break;
    const ln = cv.getUint16(p + 28, true), lx = cv.getUint16(p + 30, true), lc = cv.getUint16(p + 32, true);
    ents.push({ nome: dec.decode(cd.subarray(p + 46, p + 46 + ln)), metodo: cv.getUint16(p + 10, true), comp: cv.getUint32(p + 20, true), tam: cv.getUint32(p + 24, true), off: cv.getUint32(p + 42, true) });
    p += 46 + ln + lx + lc;
  }
  const inicio = async (e: Entrada, quer: number) => {
    const lh = await faixa(e.off, e.off + 29), lv = new DataView(lh.buffer);
    const dados = e.off + 30 + lv.getUint16(26, true) + lv.getUint16(28, true);
    const bruto = await faixa(dados, dados + Math.min(e.comp, 65536) - 1);
    if (e.metodo === 0) return bruto.subarray(0, quer);
    if (e.metodo !== 8) return new Uint8Array();
    const ds = new DecompressionStream("deflate-raw"), w = ds.writable.getWriter(), rd = ds.readable.getReader();
    w.write(bruto).catch(() => {}); if (e.comp <= 65536) w.close().catch(() => {});
    const out: number[] = [];
    const lim = setTimeout(() => rd.cancel().catch(() => {}), 3000);
    try { while (out.length < quer) { const { value, done } = await rd.read(); if (done) break; for (const b of value) { out.push(b); if (out.length >= quer) break; } } } catch { /* zip truncado no meio: usa o que já saiu */ }
    clearTimeout(lim); rd.cancel().catch(() => {});
    return new Uint8Array(out);
  };
  let stl = 0, html = 0;
  const vistos: string[] = [];
  for (const e of ents.slice(0, 60)) {
    const nm = e.nome.toLowerCase();
    if (nm.endsWith(".stl") && e.tam >= 684) {
      const b = await inicio(e, 4096);
      if (b.length >= 84) {
        const tri = new DataView(b.buffer, b.byteOffset).getUint32(80, true), txt = dec.decode(b.subarray(0, 4096)).toLowerCase();
        const bin = tri >= 10 && 84 + 50 * tri === e.tam, asc = txt.trimStart().startsWith("solid") && txt.includes("facet") && txt.includes("vertex");
        if (bin || asc) { stl++; vistos.push(e.nome); }
      }
    } else if (/\.html?$/.test(nm) && e.tam >= 1024) {
      const t = dec.decode(await inicio(e, 8192)).toLowerCase();
      if (/<!doctype html|<html|<head|<script|<body/.test(t)) { html++; vistos.push(e.nome); }
    }
  }
  return { ok: true, stl, html, arquivos: vistos.slice(0, 10), v: 1, em: new Date().toISOString() };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json(405, { erro: "Método não permitido" });

  const acc = Deno.env.get("R2_ACCOUNT_ID")?.trim(), kid = Deno.env.get("R2_ACCESS_KEY_ID")?.trim();
  const sec = Deno.env.get("R2_SECRET_ACCESS_KEY")?.trim(), bucket = Deno.env.get("R2_BUCKET")?.trim();
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
    // Diagnóstico: confere se as chaves do R2 e o nome do bucket batem (só registra no log do servidor).
    try {
      const t = await r2.fetch(`${base}?list-type=2&max-keys=1`, { method: "GET" });
      if (!t.ok) console.error("r2 recusou:", t.status, (await t.text()).slice(0, 300), "bucket:", bucket, "conta:", acc.slice(0, 6));
      else console.log("r2 ok: chaves e bucket conferem");
    } catch (er) { console.error("r2 sem conexao:", String(er)); }
    return json(200, { key, url: await assinar("PUT", key, 3600) });
  }

  // Print do scanbody (imagem pequena) no R2: sem registro em "arquivos", só a chave fica no pedido.
  const SBKEY = new RegExp(`^${user.id}/[0-9a-f-]{36}/sb-[0-9a-f-]{36}\\.(webp|jpg|png)$`, "i");
  if (acao === "sb_preparar") {
    const ext = ["webp", "jpg", "png"].includes(String(body.ext)) ? String(body.ext) : "webp";
    if (!(await pedidoDoUsuario(body.pedido_id))) return json(404, { erro: "Pedido não encontrado" });
    const key = `${user.id}/${body.pedido_id}/sb-${crypto.randomUUID()}.${ext}`;
    return json(200, { key, url: await assinar("PUT", key, 900) });
  }
  if (acao === "sb_url") {
    const key = String(body.key ?? "");
    if (!SBKEY.test(key)) return json(400, { erro: "Imagem inválida" });
    return json(200, { url: await assinar("GET", key, 3600) });
  }
  if (acao === "sb_apagar") {
    const key = String(body.key ?? "");
    if (!SBKEY.test(key)) return json(400, { erro: "Imagem inválida" });
    await r2.fetch(objUrl(key), { method: "DELETE" });
    return json(200, { ok: true });
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
    let conteudo: unknown = null;
    try { conteudo = await confereZip(r2, objUrl(key), tamanho); } catch (er) { conteudo = { ok: false, motivo: String(er).slice(0, 80) }; }
    await admin.from("arquivos").update({ conteudo }).eq("id", data.id);
    return json(200, { ...data, conteudo });
  }

  // Confere arquivos antigos (enviados antes da conferência existir). Só do próprio usuário.
  if (acao === "verificar") {
    const ids = (Array.isArray(body.ids) ? body.ids : []).map(String).filter((x: string) => UUID.test(x)).slice(0, 20);
    const { data: lista } = ids.length ? await userClient.from("arquivos").select("id,storage_key,tamanho_zip,conteudo,origem").in("id", ids) : { data: [] };
    const res: Record<string, unknown> = {};
    for (const a of lista ?? []) {
      if (a.conteudo || a.origem !== "upload" || !a.storage_key || !String(a.storage_key).startsWith(user.id + "/")) { res[a.id] = a.conteudo; continue; }
      let c: unknown;
      try { c = await confereZip(r2, objUrl(a.storage_key), Number(a.tamanho_zip)); } catch (er) { c = { ok: false, motivo: String(er).slice(0, 80) }; }
      await admin.from("arquivos").update({ conteudo: c }).eq("id", a.id);
      res[a.id] = c;
    }
    return json(200, { conteudo: res });
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
