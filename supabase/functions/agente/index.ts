// Ideali CAD · Agentes de IA (conversa livre com Ana, Bia, Mika, Klose e Sr. Otávio).
// A IA roda no Cloudflare Workers AI. A chave fica só aqui no servidor (segredo CF_AI_TOKEN).
// Os números (atrasos, quem deve, metas) continuam sendo calculados pelo app; a IA só conversa.
// Proteções: login obrigatório, assunto bloqueado fora do sistema, trava contra abuso por conta
// e teto diário do sistema inteiro (para o custo nunca passar de ~US$ 1 por dia).
import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

const MAX_CONTA = 100;      // perguntas por conta por dia (só contra abuso)
const MAX_SISTEMA = 4000;   // perguntas por dia no sistema todo (~US$ 0,80 acima do grátis)
const MODELO = Deno.env.get("CF_AI_MODELO") || "@cf/meta/llama-3.1-8b-instruct-fp8-fast";

const AGENTES: Record<string, { nome: string; papel: string; jeito: string; fora: string }> = {
  ger: { nome: "Sr. Otávio", papel: "gerente: metas do mês e do dia, cobra a equipe e dá presente quando a meta é batida",
    jeito: "sério, direto, um pouco rabugento, mas justo", fora: "Isso não é assunto de trabalho. Vamos focar na meta!" },
  ven: { nome: "Ana", papel: "vendas: pedidos novos, prazos, atrasos, ritmo de vendas do mês e clientes que mais compram",
    jeito: "simpática, animada e prestativa", fora: "Ih, isso foge do meu setor! 😅 Eu cuido das suas vendas e dos prazos. Quer saber como estão os pedidos?" },
  fin: { nome: "Bia", papel: "financeiro: quanto entrou, quem está devendo, cobranças, Pix e pagamentos",
    jeito: "esperta, prática e de olho no dinheiro", fora: "Ih, isso foge do meu setor! 😅 Eu cuido do seu financeiro. Quer saber quem está te devendo?" },
  mkt: { nome: "Mika", papel: "marketing: mensagens para clientes no WhatsApp, clientes sumidos, novos e perdidos, divulgação e datas especiais",
    jeito: "criativa, descolada e cheia de ideias", fora: "Haha, aí não é comigo! 😎 Eu cuido do seu marketing. Quer uma mensagem pronta para algum cliente?" },
  dad: { nome: "Klose", papel: "análise de dados: entregas no prazo, tempo de entrega, ajustes, qualidade e concentração de clientes",
    jeito: "calmo, analítico e didático", fora: "Isso está fora da minha análise. 📊 Eu cuido dos números do seu negócio. Quer que eu explique algum deles?" },
};

// Assuntos claramente fora do sistema: nem chegam na IA (não gastam nada).
const FORA = /\b(cachorr|gat[oa]s?\b|pet\b|futebol|time de|jogo d[eo]|novela|filme|s[ée]rie|m[úu]sica|cantor|receita de|bolo|culin[áa]ria|pol[íi]tic|elei[çc]|presidente|religi|namor|paquer|sexo|hor[óo]scopo|signo|bitcoin|cripto|aposta|bet\b|loteria|piada|poema|letra de|tarefa da escola|li[çc][ãa]o de casa)/i;

const sistema = (a: { nome: string; papel: string; jeito: string }, contexto: string) =>
`Você é ${a.nome}, agente de IA do Ideali CAD, um sistema para cadistas odontológicos (quem desenha próteses no computador, como coroas, facetas e protocolos, para dentistas e laboratórios).
Seu setor: ${a.papel}. Seu jeito: ${a.jeito}.
Regras:
- Responda SEMPRE em português do Brasil, curto (no máximo 5 frases), como numa conversa de WhatsApp.
- Fale só sobre o negócio do cadista e o Ideali CAD: pedidos, clientes, prazos, cobrança, metas, marketing para dentistas e laboratórios, arquivos STL/HTML e o uso do sistema.
- Se a pergunta for sobre qualquer outro assunto, responda exatamente: FORA_DO_ASSUNTO
- Use apenas os dados abaixo. Não invente números, nomes nem valores. Se não souber, diga que não tem essa informação.
- Não dê conselho médico, jurídico ou de investimento.
- Pacientes aparecem só com iniciais; nunca peça o nome completo do paciente.
Dados do cadista hoje:
${contexto}`;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json(405, { erro: "Método não permitido" });

  const acc = Deno.env.get("CF_ACCOUNT_ID") || Deno.env.get("R2_ACCOUNT_ID"), tok = Deno.env.get("CF_AI_TOKEN");
  if (!acc || !tok) return json(503, { erro: "A IA dos agentes ainda não foi configurada." });

  const url = Deno.env.get("SUPABASE_URL")!;
  const userClient = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } });
  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data: { user }, error: eu } = await userClient.auth.getUser();
  if (eu || !user) return json(401, { erro: "Não autenticado" });

  const body = await req.json().catch(() => ({}));
  const a = AGENTES[String(body?.agente)];
  const pergunta = String(body?.pergunta ?? "").trim().slice(0, 500);
  const contexto = String(body?.contexto ?? "").slice(0, 4000);
  const hist = Array.isArray(body?.historico) ? body.historico.slice(-6) : [];
  if (!a || !pergunta) return json(400, { erro: "Pergunta inválida" });

  if (FORA.test(pergunta)) return json(200, { resposta: a.fora, fora: true });

  const { data: lim, error: el } = await admin.rpc("ia_consumir", { uid: user.id, max_conta: MAX_CONTA, max_sistema: MAX_SISTEMA });
  if (el) return json(500, { erro: "Não consegui conferir o limite agora." });
  if (!lim?.ok) return json(429, { erro: lim?.motivo === "conta" ? "limite_conta" : "limite_sistema" });

  const msgs = [{ role: "system", content: sistema(a, contexto) }];
  for (const m of hist) {
    const t = String(m?.t ?? "").slice(0, 600);
    if (t) msgs.push({ role: m?.r === "a" ? "assistant" : "user", content: t });
  }
  msgs.push({ role: "user", content: pergunta });

  const r = await fetch(`https://api.cloudflare.com/client/v4/accounts/${acc}/ai/run/${MODELO}`, {
    method: "POST",
    headers: { Authorization: `Bearer ${tok}`, "Content-Type": "application/json" },
    body: JSON.stringify({ messages: msgs, max_tokens: 350, temperature: 0.5 }),
  });
  const j = await r.json().catch(() => null);
  if (!r.ok || !j?.success) return json(502, { erro: "A IA não respondeu agora." });
  let resp = String(j.result?.response ?? "").trim();
  if (!resp || /FORA_DO_ASSUNTO/.test(resp)) return json(200, { resposta: a.fora, fora: true });
  return json(200, { resposta: resp.slice(0, 1500) });
});
