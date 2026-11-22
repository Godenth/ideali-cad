// mika-criar-pecas — gera peças (stories/posts/carrosséis) com a Mika e renderiza os slides em PNG.
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import satori from 'https://esm.sh/satori@0.11.3'
import { initWasm, Resvg } from 'https://esm.sh/@resvg/resvg-wasm@2.6.2'
import { mikaJSON } from '../_shared/mika-ia.ts'

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}
const jsonResp = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
  })

const URL_WASM = 'https://esm.sh/@resvg/resvg-wasm@2.6.2/resvg_wasm_bg.wasm'
const URL_FONTE = 'https://fonts.gstatic.com/s/inter/v13/UcCO3FwrK3iLTeHuS_fvQtMwCp50KnMw2boKoduKmMEVuLyfAZ9hiJ-Ek-_EeA.woff2'
const LIMITE_DIARIO = 20

let wasmPronto = false
async function garantirWasm(): Promise<void> {
  if (wasmPronto) return
  try {
    await initWasm({ url: URL_WASM })
  } catch {
    const buf = await (await fetch(URL_WASM)).arrayBuffer()
    await initWasm({ wasm: buf })
  }
  wasmPronto = true
}

let fonteBuf: ArrayBuffer | null = null
async function garantirFonte(): Promise<ArrayBuffer> {
  if (!fonteBuf) {
    const r = await fetch(URL_FONTE)
    if (!r.ok) throw new Error(`fonte ${r.status}`)
    fonteBuf = await r.arrayBuffer()
  }
  return fonteBuf
}

type Slide = { layout: string; titulo?: string; texto?: string; print_index?: number }
type Peca = { tipo: string; slides: Slide[]; legenda?: string; hashtags?: string; horario_sugerido?: string }
type Midia = { id: string; arquivo_url: string | null; descricao: string | null }
type Perfil = {
  nome_marca: string
  instagram_handle: string
  o_que_faz: string
  publico_alvo: string
  tom_de_voz: string
  temas_pode: string
  temas_proibidos: string
  cta_padrao: string
  cor_principal: string
  cor_secundaria: string
  fonte: string
  logo_url: string | null
}
type No = { type: string; props: Record<string, unknown> }
type Ctx = {
  W: number
  H: number
  corPrincipal: string
  corSecundaria: string
  nomeMarca: string
  logoUrl: string | null
  instagram: string
  cta: string
  midias: Midia[]
}

function no(tipo: string, props: Record<string, unknown> = {}): No {
  return { type: tipo, props }
}
function caixa(tipo: string, style: Record<string, unknown>, children: unknown[] = []): No {
  return { type: tipo, props: { style, children } }
}
function texto(style: Record<string, unknown>, conteudo: string): No {
  return caixa('div', style, [conteudo])
}

function montarSlide(slide: Slide, ctx: Ctx, indice: number): No {
  const { W, H } = ctx
  const base = { width: W, height: H, fontFamily: 'Inter, sans-serif', position: 'relative' } as Record<string, unknown>

  if (slide.layout === 'capa') {
    const corTitulo = ctx.corSecundaria.toLowerCase() === ctx.corPrincipal.toLowerCase() ? '#FFFFFF' : ctx.corSecundaria
    const filhos: unknown[] = []
    if (ctx.logoUrl) filhos.push(no('img', { src: ctx.logoUrl, style: { width: 220, height: 220, objectFit: 'contain' } }))
    filhos.push(texto({ color: '#FFFFFF', fontSize: 104, fontWeight: 700, lineHeight: 1.1, textAlign: 'center' }, ctx.nomeMarca))
    if (slide.titulo) filhos.push(texto({ color: corTitulo, fontSize: 60, fontWeight: 600, maxWidth: W - 160, textAlign: 'center', lineHeight: 1.2 }, slide.titulo))
    return caixa('div', { ...base, backgroundColor: ctx.corPrincipal, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 48, padding: 80 }, filhos)
  }

  if (slide.layout === 'dica') {
    const filhos: unknown[] = [
      caixa('div', { position: 'absolute', top: 0, left: 0, width: 28, height: H, backgroundColor: ctx.corPrincipal }),
      texto({ color: ctx.corPrincipal, fontSize: 72, fontWeight: 700, lineHeight: 1.15, marginBottom: 32 }, slide.titulo ?? ''),
      texto({ color: '#1A1A2E', fontSize: 44, lineHeight: 1.35 }, slide.texto ?? ''),
      texto({ color: '#8A8A9A', fontSize: 30, marginTop: 48 }, ctx.instagram),
    ]
    return caixa('div', { ...base, backgroundColor: '#FFFFFF', display: 'flex', flexDirection: 'column', justifyContent: 'center', padding: 100 }, filhos)
  }

  if (slide.layout === 'print') {
    const midia = typeof slide.print_index === 'number' ? ctx.midias[slide.print_index] : null
    const filhos: unknown[] = []
    if (midia?.arquivo_url) {
      filhos.push(no('img', {
        src: midia.arquivo_url,
        style: { position: 'absolute', top: 0, left: 0, width: W, height: Math.round(H * 0.6), objectFit: 'cover' },
      }))
    }
    filhos.push(caixa('div', {
      position: 'absolute', left: 0, bottom: 0, width: W, padding: '70px 80px',
      backgroundColor: 'rgba(10,10,20,0.72)', display: 'flex', flexDirection: 'column', gap: 18,
    }, [
      texto({ color: '#FFFFFF', fontSize: 60, fontWeight: 700, lineHeight: 1.15 }, slide.titulo ?? ''),
      texto({ color: '#D8D8E2', fontSize: 40, lineHeight: 1.3 }, slide.texto ?? ''),
    ]))
    return caixa('div', { ...base, backgroundColor: ctx.corSecundaria }, filhos)
  }

  if (slide.layout === 'passo') {
    return caixa('div', { ...base, backgroundColor: '#FFFFFF', display: 'flex', flexDirection: 'row', alignItems: 'center', padding: 100, gap: 70 }, [
      texto({ color: ctx.corPrincipal, fontSize: 260, fontWeight: 700, lineHeight: 1 }, String(indice + 1)),
      caixa('div', { display: 'flex', flexDirection: 'column', gap: 28, flex: 1 }, [
        texto({ color: ctx.corPrincipal, fontSize: 68, fontWeight: 700, lineHeight: 1.15 }, slide.titulo ?? ''),
        texto({ color: '#1A1A2E', fontSize: 44, lineHeight: 1.35 }, slide.texto ?? ''),
      ]),
    ])
  }

  if (slide.layout === 'impacto') {
    return caixa('div', { ...base, backgroundColor: ctx.corSecundaria, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', padding: 100, gap: 32, textAlign: 'center' }, [
      texto({ color: ctx.corPrincipal, fontSize: 200, fontWeight: 700, lineHeight: 1 }, slide.texto ?? slide.titulo ?? ''),
      texto({ color: '#FFFFFF', fontSize: 48, fontWeight: 600, maxWidth: W - 200, lineHeight: 1.25 }, slide.titulo && slide.texto ? slide.titulo : ''),
    ])
  }

  if (slide.layout === 'cta') {
    const filhos: unknown[] = []
    if (ctx.logoUrl) filhos.push(no('img', { src: ctx.logoUrl, style: { width: 200, height: 200, objectFit: 'contain' } }))
    filhos.push(texto({ color: '#FFFFFF', fontSize: 96, fontWeight: 700, textAlign: 'center' }, ctx.nomeMarca))
    filhos.push(texto({ color: '#FFFFFF', fontSize: 52, fontWeight: 600, textAlign: 'center', maxWidth: W - 160 }, ctx.cta))
    filhos.push(texto({ color: '#FFFFFF', fontSize: 40, opacity: 0.85, textAlign: 'center' }, ctx.instagram))
    return caixa('div', { ...base, backgroundColor: ctx.corPrincipal, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 40, padding: 80 }, filhos)
  }

  return caixa('div', { ...base, backgroundColor: '#FFFFFF', display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 80 }, [
    texto({ color: '#1A1A2E', fontSize: 52, textAlign: 'center' }, slide.titulo ?? slide.texto ?? ''),
  ])
}

async function renderPNG(arvore: No, largura: number, altura: number): Promise<Uint8Array> {
  const fonte = await garantirFonte()
  const svg = await satori(arvore as never, {
    width: largura,
    height: altura,
    fonts: [
      { name: 'Inter', data: fonte, weight: 400, style: 'normal' },
      { name: 'Inter', data: fonte, weight: 700, style: 'normal' },
    ],
  })
  const resvg = new Resvg(svg, { fitTo: { mode: 'width', value: largura } })
  return resvg.render().asPng()
}

function validarTexto(peca: Peca): { error: string; slide: number } | null {
  for (let i = 0; i < peca.slides.length; i++) {
    const s = peca.slides[i]
    if (s.titulo && s.titulo.length > 60) return { error: 'texto_longo', slide: i }
    if (s.texto && s.texto.length > 200) return { error: 'texto_longo', slide: i }
  }
  return null
}

function montarPrompt(perfil: Perfil, tema: { nome: string; texto_base: string | null }, midias: Midia[], total: number): string {
  const listaMidias = midias.length
    ? midias.map((m, i) => `[${i}] ${m.descricao ?? '(imagem sem descrição)'}`).join('\n')
    : '(nenhuma imagem disponível neste tema)'
  return `Você é a Mika, a assistente de marketing do Estúdio da Mika. Crie ${total} peça(s) de conteúdo para o Instagram.

PERFIL DA MARCA
- Nome: ${perfil.nome_marca}
- Instagram: ${perfil.instagram_handle}
- O que faz: ${perfil.o_que_faz}
- Público-alvo: ${perfil.publico_alvo}
- Tom de voz: ${perfil.tom_de_voz}
- Temas permitidos: ${perfil.temas_pode}
- Temas proibidos: ${perfil.temas_proibidos}
- CTA padrão: ${perfil.cta_padrao}

TEMA
- Nome: ${tema.nome}
- Texto base (use SOMENTE informações daqui, nunca invente):
"""
${tema.texto_base ?? '(sem texto base)'}
"""

IMAGENS DISPONÍVEIS (referência por índice para o campo print_index):
${listaMidias}

REGRAS
- Português correto, frases curtas, 1 ideia por slide.
- Cada peça tem tipo: "story", "feed" ou "carrossel".
- Carrossel: 4 a 7 slides, começando com layout "capa" e terminando com layout "cta".
- Layouts disponíveis: capa, dica, print, passo, impacto, cta.
- No layout "print", use print_index apontando para uma das imagens acima.
- Título de até 60 caracteres, texto de até 200 caracteres por slide.
- De 5 a 15 hashtags por peça.
- horario_sugerido no formato ISO (ex.: 2026-05-01T18:00:00-03:00).

Responda APENAS com JSON válido no formato:
{ "pecas": [ { "tipo": "story|feed|carrossel", "slides": [ { "layout": "capa", "titulo": "...", "texto": "...", "print_index": 0 } ], "legenda": "...", "hashtags": "...", "horario_sugerido": "..." } ] }`
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })
  if (req.method !== 'POST') return jsonResp(405, { error: 'Método não permitido' })

  const auth = req.headers.get('authorization') ?? ''
  const tokenUsuario = auth.startsWith('Bearer ') ? auth.slice(7).trim() : ''
  if (!tokenUsuario) return jsonResp(401, { error: 'Não autenticado' })

  const sbUrl = Deno.env.get('SUPABASE_URL')!
  const sbServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

  let clienteId: string
  try {
    const sbAnon = Deno.env.get('SUPABASE_ANON_KEY') ?? sbServiceKey
    const sbUser = createClient(sbUrl, sbAnon, {
      global: { headers: { Authorization: `Bearer ${tokenUsuario}` } },
    })
    const { data, error } = await sbUser.auth.getUser()
    if (error || !data.user) return jsonResp(401, { error: 'Não autenticado' })
    clienteId = data.user.id
  } catch {
    return jsonResp(401, { error: 'Não autenticado' })
  }

  const sb = createClient(sbUrl, sbServiceKey)

  let body: Record<string, unknown>
  try {
    body = await req.json() as Record<string, unknown>
  } catch {
    return jsonResp(400, { error: 'Corpo inválido' })
  }

  const temaId = String(body.tema_id ?? '')
  if (!temaId) return jsonResp(400, { error: 'tema_id obrigatório' })

  const nStories = body.n_stories === undefined ? 1 : Math.max(0, parseInt(String(body.n_stories)) || 0)
  const nPosts = body.n_posts === undefined ? 1 : Math.max(0, parseInt(String(body.n_posts)) || 0)
  const nCarrosels = body.n_carrosels === undefined ? 1 : Math.max(0, parseInt(String(body.n_carrosels)) || 0)
  const total = nStories + nPosts + nCarrosels

  const hoje = new Date().toISOString().slice(0, 10)
  const { data: uso } = await sb
    .from('mkt_mika_uso')
    .select('pecas')
    .eq('cliente_id', clienteId)
    .eq('dia', hoje)
    .maybeSingle()
  const usado = uso?.pecas ?? 0
  if (usado + total > LIMITE_DIARIO) {
    return jsonResp(429, { error: 'Limite de 20 peças por dia atingido' })
  }

  const { data: tema, error: temaErr } = await sb
    .from('mkt_temas')
    .select('*')
    .eq('id', temaId)
    .eq('cliente_id', clienteId)
    .maybeSingle()
  if (temaErr || !tema) return jsonResp(404, { error: 'Tema não encontrado' })

  const { data: midias } = await sb
    .from('mkt_tema_midias')
    .select('*')
    .eq('tema_id', temaId)
    .eq('tipo', 'imagem')
    .eq('ativo', true)

  const { data: perfil } = await sb
    .from('mkt_perfil_marca')
    .select('*')
    .eq('cliente_id', clienteId)
    .maybeSingle()

  const ctxPerfil: Perfil = {
    nome_marca: perfil?.nome_marca ?? 'Sua Marca',
    instagram_handle: perfil?.instagram_handle ?? '',
    o_que_faz: perfil?.o_que_faz ?? '',
    publico_alvo: perfil?.publico_alvo ?? '',
    tom_de_voz: perfil?.tom_de_voz ?? '',
    temas_pode: perfil?.temas_pode ?? '',
    temas_proibidos: perfil?.temas_proibidos ?? '',
    cta_padrao: perfil?.cta_padrao ?? '',
    cor_principal: perfil?.cor_principal ?? '#2F6FD6',
    cor_secundaria: perfil?.cor_secundaria ?? '#1A1A2E',
    fonte: perfil?.fonte ?? 'Inter',
    logo_url: perfil?.logo_url ?? null,
  }

  let resultado: unknown
  try {
    resultado = await mikaJSON(montarPrompt(ctxPerfil, tema as { nome: string; texto_base: string | null }, (midias ?? []) as Midia[], total))
  } catch (e) {
    return jsonResp(502, { error: e instanceof Error ? e.message : 'Falha ao gerar com a IA' })
  }

  const pecas = ((resultado as { pecas?: Peca[] })?.pecas ?? []).filter((p) => p && Array.isArray(p.slides))
  if (!pecas.length) return jsonResp(502, { error: 'A IA não devolveu peças' })

  await garantirWasm()

  const posts: Array<{ id: string; tipo: string; slides_count: number; horario_sugerido: string | null }> = []
  try {
    for (const peca of pecas) {
      const invalido = validarTexto(peca)
      if (invalido) return jsonResp(422, invalido)

      const largura = 1080
      const altura = peca.tipo === 'story' ? 1920 : 1350
      const ctx: Ctx = {
        W: largura,
        H: altura,
        corPrincipal: ctxPerfil.cor_principal,
        corSecundaria: ctxPerfil.cor_secundaria,
        nomeMarca: ctxPerfil.nome_marca,
        logoUrl: ctxPerfil.logo_url,
        instagram: ctxPerfil.instagram_handle,
        cta: ctxPerfil.cta_padrao,
        midias: (midias ?? []) as Midia[],
      }

      const postId = crypto.randomUUID()
      const slidesOut: Array<Record<string, unknown>> = []
      for (let i = 0; i < peca.slides.length; i++) {
        const arvore = montarSlide(peca.slides[i], ctx, i)
        const png = await renderPNG(arvore, largura, altura)
        const path = `${clienteId}/pecas/${postId}/${i}.png`
        const { error: upErr } = await sb.storage.from('marketing').upload(path, png, {
          contentType: 'image/png',
          upsert: true,
        })
        if (upErr) throw new Error(`upload slide ${i}: ${upErr.message}`)
        slidesOut.push({
          layout: peca.slides[i].layout,
          titulo: peca.slides[i].titulo ?? null,
          texto: peca.slides[i].texto ?? null,
          print_index: peca.slides[i].print_index ?? null,
          png_path: path,
        })
      }

      const agendado = peca.horario_sugerido
        ? new Date(peca.horario_sugerido)
        : new Date(Date.now() + 24 * 60 * 60 * 1000)
      const { data: post, error: insErr } = await sb
        .from('posts_agendados')
        .insert({
          id: postId,
          cliente_id: clienteId,
          tipo: peca.tipo,
          legenda: [peca.legenda, peca.hashtags].filter(Boolean).join('\n') || null,
          hashtags: peca.hashtags ?? null,
          agendado_para: agendado.toISOString(),
          status: 'aguardando',
          gerado_por_mika: true,
          tema_id: temaId,
          horario_sugerido: peca.horario_sugerido ?? null,
          slides: slidesOut,
        })
        .select('id')
        .single()
      if (insErr) throw new Error(`posts_agendados: ${insErr.message}`)

      posts.push({
        id: post!.id,
        tipo: peca.tipo,
        slides_count: slidesOut.length,
        horario_sugerido: peca.horario_sugerido ?? null,
      })
    }
  } catch (e) {
    return jsonResp(502, { error: e instanceof Error ? e.message : 'Erro ao renderizar peças' })
  }

  await sb.from('mkt_mika_uso').upsert({
    cliente_id: clienteId,
    dia: hoje,
    pecas: usado + posts.length,
  }, { onConflict: 'cliente_id,dia' })

  return jsonResp(200, { ok: true, posts })
})
