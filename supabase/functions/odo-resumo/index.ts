// Ideali Odonto · Resumo diário por e-mail (Resend).
// Duas formas de chamar:
//  1) O agendamento diário do banco (pg_cron) manda o cabeçalho x-resumo com o segredo guardado no Vault
//     -> envia o resumo para todas as contas que ligaram "Receber o resumo diário".
//  2) O botão "Enviar um teste agora" do app manda o login do usuário -> envia só o resumo dele, para ele.
// O e-mail vai SEMPRE para o e-mail de login da própria conta (nunca para um endereço digitado).
// Segredos usados (ficam no servidor, nunca no site): RESEND_API_KEY e a chave de serviço automática do Supabase.
import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-resumo",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

const URL_SB = Deno.env.get("SUPABASE_URL")!;
const SERVICO = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const RESEND = Deno.env.get("RESEND_API_KEY") ?? "";
const REMETENTE = Deno.env.get("RESUMO_REMETENTE") ?? "Ideali Odonto <onboarding@resend.dev>";
const db = createClient(URL_SB, SERVICO, { auth: { persistSession: false } });
const ultimoTeste = new Map<string, number>();

const MESES = ["janeiro","fevereiro","março","abril","maio","junho","julho","agosto","setembro","outubro","novembro","dezembro"];
const esc = (s: unknown) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!));
const R$ = (v: number) => "R$ " + (Math.round(v * 100) / 100).toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const hojeBR = () => new Date(Date.now() - 3 * 3600e3).toISOString().slice(0, 10);
const dBR = (iso: string) => iso.slice(0, 10).split("-").reverse().join("/");
function util5(ano: number, mes: number) { // 5º dia útil do mês seguinte ao mês de referência
  const d = new Date(Date.UTC(ano, mes, 1, 12)); let k = 0;
  for (;;) { const w = d.getUTCDay(); if (w !== 0 && w !== 6 && ++k === 5) break; d.setUTCDate(d.getUTCDate() + 1); }
  return d.toISOString().slice(0, 10);
}
async function todos(t: string, uid: string, extra?: (q: any) => any) {
  let out: any[] = [];
  for (let i = 0; ; i += 1000) {
    let q = db.from(t).select("*").eq("user_id", uid);
    if (extra) q = extra(q);
    const { data, error } = await q.range(i, i + 999);
    if (error) throw error;
    out = out.concat(data ?? []);
    if ((data ?? []).length < 1000) return out;
  }
}

async function montar(uid: string) {
  const hoje = hojeBR();
  const ontem = new Date(Date.parse(hoje + "T12:00:00Z") - 864e5).toISOString().slice(0, 10);
  const [emp, cfg, cli, meses, pags, peds] = await Promise.all([
    db.from("odo_empresas").select("nome").eq("user_id", uid).maybeSingle(),
    db.from("odo_fin_config").select("*").eq("user_id", uid).maybeSingle(),
    todos("odo_clientes", uid),
    todos("odo_fin_meses", uid),
    todos("odo_fin_pagamentos", uid),
    todos("odo_pedidos", uid, (q) => q.eq("apagado", false).eq("arquivado", false)),
  ]);
  const nomeCli = new Map(cli.map((c: any) => [c.id, c.nome]));
  const nm = (m: any) => (m.cliente_id && nomeCli.get(m.cliente_id)) || m.cliente_nome || (m.cliente_reg ? "Cliente nº " + m.cliente_reg : "Sem cliente");
  const pagoDe = new Map<string, number>();
  for (const p of pags) if (!p.anulado_em) pagoDe.set(p.mes_id, (pagoDe.get(p.mes_id) ?? 0) + Number(p.valor));

  // dinheiro
  const entrou = pags.filter((p: any) => !p.anulado_em && (p.data === ontem || String(p.criado_em).slice(0, 10) === ontem));
  const grupos = new Map<string, { nome: string; tot: number; venc: string | null }>();
  for (const m of meses) {
    const r = m.quitado ? 0 : Number(m.valor_mes) - (pagoDe.get(m.id) ?? 0);
    const k = m.cliente_id ?? "r" + m.cliente_reg;
    const g = grupos.get(k) ?? { nome: nm(m), tot: 0, venc: null };
    g.tot += r;
    if (r > 0.005) { const v = util5(m.ano, m.mes); if (!g.venc || v < g.venc) g.venc = v; }
    grupos.set(k, g);
  }
  const abertos = [...grupos.values()].filter((g) => g.tot > 0.005).sort((a, b) => b.tot - a.tot);
  const totAberto = abertos.reduce((s, g) => s + g.tot, 0);
  const vencidos = abertos.filter((g) => g.venc && g.venc < hoje);
  const pct = Number(cfg.data?.comissao_pct ?? 10) / 100;
  const comissao = meses.reduce((s: number, m: any) => s + Math.max(0, (pagoDe.get(m.id) ?? 0) - Number(m.comissionado ?? 0)) * pct, 0);

  // produção
  const des = peds.filter((p: any) => p.status === "desenho");
  const pro = peds.filter((p: any) => p.status === "producao");
  const prontos = peds.filter((p: any) => p.status === "finalizado");
  const urg = peds.filter((p: any) => (p.status === "desenho" || p.status === "producao") && p.prazo && p.prazo <= hoje)
    .sort((a: any, b: any) => (a.prazo < b.prazo ? -1 : 1));

  // avisos
  const semComp = pags.filter((p: any) => !p.anulado_em && !p.comprovante_path && !p.arquivo_legado && Date.parse(p.criado_em) > Date.now() - 30 * 864e5).length;
  const d = new Date(Date.parse(hoje + "T12:00:00Z")); d.setUTCMonth(d.getUTCMonth() - 1);
  const semExtrato = meses.filter((m: any) => m.ano === d.getUTCFullYear() && m.mes === d.getUTCMonth() + 1 && Number(m.valor_mes) > 0 && !m.extrato_path && !m.arquivo_legado).length;

  const li = (t: string) => `<li style="margin:4px 0">${t}</li>`;
  const sec = (tit: string, itens: string[]) => itens.length ? `<h2 style="font-size:16px;margin:22px 0 6px">${tit}</h2><ul style="padding-left:18px;margin:0">${itens.join("")}</ul>` : "";
  const dinheiro = [
    entrou.length ? li(`Entrou ontem: <b>${entrou.length} pagamento${entrou.length > 1 ? "s" : ""}, ${R$(entrou.reduce((s: number, p: any) => s + Number(p.valor), 0))}</b>`) : li("Nenhum pagamento lançado ontem."),
    ...vencidos.slice(0, 6).map((g) => li(`⚠️ ${esc(g.nome)}: <b>${R$(g.tot)}</b>, venceu em ${dBR(g.venc!)}`)),
    li(`Total em aberto: <b>${R$(totAberto)}</b> de ${abertos.length} cliente${abertos.length !== 1 ? "s" : ""}`),
  ];
  const producao = [
    li(`🟣 Desenhos CAD a fazer: <b>${des.length}</b>`),
    li(`Em produção: <b>${pro.length}</b> · Prontos para entregar: <b>${prontos.length}</b>`),
    ...urg.slice(0, 8).map((p: any) => li(`${p.prazo < hoje ? "⏰ Atrasado" : "📅 Vence hoje"}: #${p.numero ?? "—"} ${esc(p.paciente || "sem paciente")} (${esc(p.trabalho || p.tipo)})`)),
    ...(urg.length > 8 ? [li(`… e mais ${urg.length - 8}.`)] : []),
  ];
  const avisos = [
    ...(semComp ? [li(`${semComp} pagamento${semComp > 1 ? "s" : ""} sem comprovante nos últimos 30 dias`)] : []),
    ...(semExtrato ? [li(`${semExtrato} cliente${semExtrato > 1 ? "s" : ""} sem extrato de ${MESES[d.getUTCMonth()]}`)] : []),
    ...(comissao > 0.005 ? [li(`💜 Comissão a receber: <b>${R$(comissao)}</b>`)] : []),
  ];
  const empresa = emp.data?.nome || "seu laboratório";
  const html = `<div style="font-family:Arial,Helvetica,sans-serif;max-width:560px;margin:auto;color:#1d2433;line-height:1.45">
    <h1 style="font-size:20px;margin:0 0 4px">☀️ Bom dia! Resumo de ${dBR(hoje)}</h1><p style="margin:0;color:#667">${esc(empresa)}</p>
    ${sec("💰 Dinheiro", dinheiro)}${sec("🦷 Produção", producao)}${sec("📋 Avisos", avisos)}
    <p style="margin-top:26px"><a href="https://idealisystems.com/odonto/app" style="background:#0f7a6b;color:#fff;padding:10px 16px;border-radius:10px;text-decoration:none;font-weight:bold">Abrir o Ideali Odonto</a></p>
    <p style="color:#99a;font-size:12px;margin-top:22px">Você recebe este e-mail porque ligou o resumo diário em Financeiro › Ajustes. Para parar, desmarque lá.</p></div>`;
  return { assunto: `☀️ Resumo de hoje · ${empresa}`, html };
}

async function enviar(uid: string) {
  const { data: u, error } = await db.auth.admin.getUserById(uid);
  if (error || !u?.user?.email) throw new Error("conta sem e-mail");
  const { assunto, html } = await montar(uid);
  const r = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { Authorization: `Bearer ${RESEND}`, "Content-Type": "application/json" },
    body: JSON.stringify({ from: REMETENTE, to: [u.user.email], subject: assunto, html }),
  });
  if (!r.ok) throw new Error("Resend " + r.status + " " + (await r.text()).slice(0, 200));
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json(405, { erro: "Método não permitido" });
  if (!RESEND) return json(500, { erro: "Falta o segredo RESEND_API_KEY no Supabase" });

  const segredo = req.headers.get("x-resumo");
  if (segredo) { // agendamento diário
    const { data: ok } = await db.rpc("odo_resumo_confere", { p: segredo });
    if (ok !== true) return json(401, { erro: "Não autorizado" });
    const { data: lista } = await db.from("odo_fin_config").select("user_id").eq("resumo_ativo", true);
    let enviados = 0; const falhas: string[] = [];
    for (const c of lista ?? []) { try { await enviar(c.user_id); enviados++; } catch (e) { falhas.push(String(e).slice(0, 120)); } }
    return json(200, { enviados, falhas: falhas.length });
  }

  // teste pelo app: só para o próprio usuário logado
  const token = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data: quem } = await db.auth.getUser(token);
  const uid = quem?.user?.id;
  if (!uid) return json(401, { erro: "Entre na sua conta" });
  const ult = ultimoTeste.get(uid) ?? 0;
  if (Date.now() - ult < 60e3) return json(429, { erro: "Espere um minuto para mandar outro teste" });
  ultimoTeste.set(uid, Date.now());
  try { await enviar(uid); return json(200, { ok: true }); }
  catch (e) { console.error(e); return json(502, { erro: "Não consegui enviar o e-mail agora" }); }
});
