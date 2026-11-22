// mika-ia.ts — provedor de IA trocável (Cloudflare Workers AI | Anthropic)
// Escolha: env MIKA_IA = cloudflare (padrão) | anthropic

const PROVEDOR = Deno.env.get('MIKA_IA') ?? 'cloudflare'

// ---- Cloudflare Workers AI --------------------------------
const CF_TOKEN   = () => Deno.env.get('CF_AI_TOKEN')!
const CF_ACCOUNT = () => Deno.env.get('CF_ACCOUNT_ID')!
// Modelos — altere aqui se quiser trocar
const CF_MODELO_TEXTO  = '@cf/meta/llama-3.3-70b-instruct-fp8-fast'
const CF_MODELO_VISAO  = '@cf/unum/uform-gen2-qwen-500m'

// ---- Anthropic -------------------------------------------
const ANT_KEY    = () => Deno.env.get('ANTHROPIC_API_KEY')!
const ANT_MODELO_GRANDE = 'claude-sonnet-5-5'
const ANT_MODELO_SIMPLES = 'claude-haiku-5-5'

// Valida JSON e tenta 1 vez corrigir se vier inválido
async function tentaJSON(chamarIA: () => Promise<string>): Promise<unknown> {
  for (let i = 0; i < 2; i++) {
    const txt = await chamarIA()
    // extrai o bloco JSON (pode vir com markdown ```json ... ```)
    const match = txt.match(/```json\s*([\s\S]*?)```/) || txt.match(/(\{[\s\S]*\}|\[[\s\S]*\])/)
    const raw = match ? (match[1] ?? match[0]) : txt
    try { return JSON.parse(raw.trim()) } catch { /* tenta de novo */ }
  }
  throw new Error('IA devolveu JSON inválido após 2 tentativas')
}

// ---- Cloudflare text -------------------------------------
async function cfTexto(prompt: string): Promise<string> {
  const r = await fetch(
    `https://api.cloudflare.com/client/v4/accounts/${CF_ACCOUNT()}/ai/run/${CF_MODELO_TEXTO}`,
    {
      method: 'POST',
      headers: { Authorization: `Bearer ${CF_TOKEN()}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ messages: [{ role: 'user', content: prompt }], max_tokens: 4096 }),
    }
  )
  if (!r.ok) throw new Error(`CF AI texto ${r.status}: ${await r.text()}`)
  const d = await r.json() as { result?: { response?: string } }
  return d.result?.response ?? ''
}

// ---- Cloudflare vision -----------------------------------
async function cfVisao(imageUrl: string, prompt: string): Promise<string> {
  // busca a imagem e converte para base64
  const imgRes = await fetch(imageUrl)
  const buf = await imgRes.arrayBuffer()
  const b64 = btoa(String.fromCharCode(...new Uint8Array(buf)))
  const r = await fetch(
    `https://api.cloudflare.com/client/v4/accounts/${CF_ACCOUNT()}/ai/run/${CF_MODELO_VISAO}`,
    {
      method: 'POST',
      headers: { Authorization: `Bearer ${CF_TOKEN()}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ image: b64, prompt, max_tokens: 256 }),
    }
  )
  if (!r.ok) throw new Error(`CF AI visão ${r.status}: ${await r.text()}`)
  const d = await r.json() as { result?: { description?: string } }
  return d.result?.description ?? ''
}

// ---- Anthropic text (preparado, não ativado) -------------
async function antTexto(prompt: string, simples = false): Promise<string> {
  const model = simples ? ANT_MODELO_SIMPLES : ANT_MODELO_GRANDE
  const r = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'x-api-key': ANT_KEY(),
      'anthropic-version': '2023-06-01',
      'content-type': 'application/json',
    },
    body: JSON.stringify({ model, max_tokens: 4096, messages: [{ role: 'user', content: prompt }] }),
  })
  if (!r.ok) throw new Error(`Anthropic ${r.status}: ${await r.text()}`)
  const d = await r.json() as { content?: Array<{ text?: string }> }
  return d.content?.[0]?.text ?? ''
}

// ---- Anthropic vision (preparado) ------------------------
async function antVisao(imageUrl: string, prompt: string): Promise<string> {
  const imgRes = await fetch(imageUrl)
  const buf = await imgRes.arrayBuffer()
  const b64 = btoa(String.fromCharCode(...new Uint8Array(buf)))
  const mediaType = imgRes.headers.get('content-type') ?? 'image/jpeg'
  const r = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'x-api-key': ANT_KEY(),
      'anthropic-version': '2023-06-01',
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      model: ANT_MODELO_GRANDE,
      max_tokens: 256,
      messages: [{ role: 'user', content: [
        { type: 'image', source: { type: 'base64', media_type: mediaType, data: b64 } },
        { type: 'text', text: prompt },
      ]}],
    }),
  })
  if (!r.ok) throw new Error(`Anthropic vision ${r.status}: ${await r.text()}`)
  const d = await r.json() as { content?: Array<{ text?: string }> }
  return d.content?.[0]?.text ?? ''
}

// ---- API pública -----------------------------------------
export async function mikaTexto(prompt: string, opcoes?: { simples?: boolean }): Promise<string> {
  if (PROVEDOR === 'anthropic') return antTexto(prompt, opcoes?.simples)
  return cfTexto(prompt)
}

export async function mikaVisao(imageUrl: string, prompt: string): Promise<string> {
  if (PROVEDOR === 'anthropic') return antVisao(imageUrl, prompt)
  return cfVisao(imageUrl, prompt)
}

export async function mikaJSON(prompt: string, opcoes?: { simples?: boolean }): Promise<unknown> {
  return tentaJSON(() => mikaTexto(prompt, opcoes))
}
