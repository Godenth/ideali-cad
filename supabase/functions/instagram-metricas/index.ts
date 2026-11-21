import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const IG_BASE = 'https://graph.facebook.com/v27.0'

type MetricaValor = { value?: number; end_time?: string }

type InsightItem = {
  name: string
  period?: string
  values?: MetricaValor[]
}

type MediaItem = {
  id: string
  media_type?: string
  media_product_type?: string
  caption?: string
  permalink?: string
  thumbnail_url?: string
  media_url?: string
  timestamp?: string
}

type StoryItem = MediaItem

type SupabaseAdmin = ReturnType<typeof createClient>

function resp(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' }
  })
}

// Chamada GET/POST à Graph API. Nunca loga o token.
async function igFetch(path: string, params: Record<string, string>): Promise<any | null> {
  const url = new URL(`${IG_BASE}${path}`)
  for (const [k, v] of Object.entries(params)) {
    if (v !== undefined && v !== null) url.searchParams.set(k, v)
  }
  try {
    const r = await fetch(url.toString())
    if (!r.ok) {
      console.log(`IG fetch falhou: ${path} status=${r.status}`)
      return null
    }
    return await r.json()
  } catch (e) {
    console.log(`IG fetch erro: ${path} ${String(e)}`)
    return null
  }
}

// Extrai valor numérico — suporta formato legado (values[]) e novo (total_value.value)
function pegarValor(data: InsightItem[] | undefined | null, nome: string): number | null {
  if (!Array.isArray(data)) return null
  const item = data.find((d) => d.name === nome)
  if (!item) return null
  const tv = (item as any)?.total_value?.value
  if (typeof tv === 'number') return tv
  const v = item?.values?.[0]?.value
  return typeof v === 'number' ? v : null
}

// Insights por dia: tenta com todas as métricas; se der erro, tenta sem as opcionais
async function insightsContaDia(
  token: string,
  igUserId: string,
  since: number,
  until: number
): Promise<Record<string, number | null>> {
  const metricasCompletas =
    'reach,profile_views,total_interactions,likes,comments,shares,saves,follows_and_unfollows'
  const metricasBasicas = 'reach,profile_views,total_interactions,likes,comments,shares,saves'

  // metric_type=total_value é obrigatório para profile_views, likes, etc. (v27.0+)
  const base = { period: 'day', metric_type: 'total_value', since: String(since), until: String(until) }

  let json = await igFetch(`/${igUserId}/insights`, {
    metric: metricasCompletas,
    access_token: token,
    ...base
  })

  // Se falhou (ex: follows_and_unfollows indisponível), tenta sem ela
  if (!json || json.error) {
    json = await igFetch(`/${igUserId}/insights`, {
      metric: metricasBasicas,
      access_token: token,
      ...base
    })
  }

  const data: InsightItem[] = json?.data || []
  return {
    alcance: pegarValor(data, 'reach'),
    visitas_perfil: pegarValor(data, 'profile_views'),
    interacoes: pegarValor(data, 'total_interactions'),
    curtidas: pegarValor(data, 'likes'),
    comentarios: pegarValor(data, 'comments'),
    compartilhamentos: pegarValor(data, 'shares'),
    salvamentos: pegarValor(data, 'saves') ?? pegarValor(data, 'saved'),
    seguidores_ganhos: pegarValor(data, 'follows_and_unfollows')
  }
}

function dataLocalISO(d: Date): string {
  return d.toISOString().slice(0, 10)
}

function inicioDiaUTC(dateStr: string): Date {
  return new Date(`${dateStr}T00:00:00Z`)
}

function fimDiaUTC(dateStr: string): Date {
  return new Date(`${dateStr}T23:59:59Z`)
}

// ---------- Coleção: posts/reels ----------
async function coletarPosts(
  token: string,
  igUserId: string,
  clienteId: string,
  sbAdmin: SupabaseAdmin
): Promise<number> {
  const json = await igFetch(`/${igUserId}/media`, {
    fields: 'id,media_type,caption,permalink,thumbnail_url,timestamp,like_count,comments_count',
    limit: '100',
    access_token: token
  })
  const medias: MediaItem[] = json?.data || []
  let salvos = 0

  for (const m of medias) {
    const tipo =
      m.media_type === 'REEL' ? 'reel' : 'feed'
    const metricas = ['reach', 'likes', 'comments', 'shares', 'saved', 'total_interactions']
    if (tipo === 'reel') {
      metricas.push('ig_reels_avg_watch_time', 'clips_replays_count')
    }

    const insJson = await igFetch(`/${m.id}/insights`, {
      metric: metricas.join(','),
      period: 'lifetime',
      access_token: token
    })
    let data: InsightItem[] = insJson?.data || []

    // Se o lote completo falhou (métrica problemática), tenta o essencial
    if (!data.length) {
      const essencial = await igFetch(`/${m.id}/insights`, {
        metric: 'reach,impressions,likes,comments',
        period: 'lifetime',
        access_token: token
      })
      data = essencial?.data || []
    }

    let visualizacoes = pegarValor(data, 'impressions')
    if (visualizacoes === null) visualizacoes = pegarValor(data, 'views')

    const tempoMs = pegarValor(data, 'ig_reels_avg_watch_time')

    const linha: Record<string, unknown> = {
      cliente_id: clienteId,
      ig_media_id: m.id,
      tipo,
      legenda: m.caption ?? null,
      permalink: m.permalink ?? null,
      thumbnail_url: m.thumbnail_url ?? null,
      publicado_em: m.timestamp ?? null,
      coletado_em: new Date().toISOString(),
      visualizacoes,
      alcance: pegarValor(data, 'reach'),
      curtidas: pegarValor(data, 'likes') ?? (typeof (m as any).like_count === 'number' ? (m as any).like_count : null),
      comentarios: pegarValor(data, 'comments') ?? (typeof (m as any).comments_count === 'number' ? (m as any).comments_count : null),
      compartilhamentos: pegarValor(data, 'shares'),
      salvamentos: pegarValor(data, 'saved'),
      interacoes: pegarValor(data, 'total_interactions'),
      tempo_medio_reel: tempoMs !== null ? tempoMs / 1000 : null
    }

    const { error } = await sbAdmin
      .from('post_metricas')
      .upsert(linha, { onConflict: 'cliente_id,ig_media_id' })
    if (error) {
      console.log(`post_metricas erro media=${m.id}: ${error.message}`)
    } else {
      salvos++
    }
  }

  return salvos
}

// ---------- Coleção: stories ----------
async function coletarStories(
  token: string,
  igUserId: string,
  clienteId: string,
  sbAdmin: SupabaseAdmin
): Promise<number> {
  const json = await igFetch(`/${igUserId}/stories`, {
    fields: 'id,caption,permalink,thumbnail_url,timestamp',
    access_token: token
  })
  const stories: StoryItem[] = json?.data || []
  let salvos = 0

  for (const s of stories) {
    const insJson = await igFetch(`/${s.id}/insights`, {
      metric: 'reach,replies,exits,impressions',
      period: 'lifetime',
      access_token: token
    })
    let data: InsightItem[] = insJson?.data || []

    if (!data.length) {
      const essencial = await igFetch(`/${s.id}/insights`, {
        metric: 'reach,impressions',
        period: 'lifetime',
        access_token: token
      })
      data = essencial?.data || []
    }

    let visualizacoes = pegarValor(data, 'impressions')
    if (visualizacoes === null) visualizacoes = pegarValor(data, 'views')

    const linha: Record<string, unknown> = {
      cliente_id: clienteId,
      ig_media_id: s.id,
      tipo: 'story',
      legenda: s.caption ?? null,
      permalink: s.permalink ?? null,
      thumbnail_url: s.thumbnail_url ?? null,
      publicado_em: s.timestamp ?? null,
      coletado_em: new Date().toISOString(),
      visualizacoes,
      alcance: pegarValor(data, 'reach'),
      curtidas: null,
      comentarios: null,
      compartilhamentos: null,
      salvamentos: null,
      interacoes: null,
      tempo_medio_reel: null,
      respostas_story: pegarValor(data, 'replies'),
      saidas_story: pegarValor(data, 'exits')
    }

    const { error } = await sbAdmin
      .from('post_metricas')
      .upsert(linha, { onConflict: 'cliente_id,ig_media_id' })
    if (error) {
      console.log(`post_metricas erro story=${s.id}: ${error.message}`)
    } else {
      salvos++
    }
  }

  return salvos
}

// ---------- Coleção: métricas diárias da conta ----------
async function coletarContaDiario(
  token: string,
  igUserId: string,
  clienteId: string,
  sbAdmin: SupabaseAdmin,
  backfill: boolean,
  seguidores: number | null,
  mediaCount: number | null
): Promise<number> {
  const hoje = new Date()
  const dias: string[] = []

  if (backfill) {
    for (let i = 1; i <= 30; i++) {
      const d = new Date(hoje.getTime())
      d.setUTCDate(d.getUTCDate() - i)
      dias.push(dataLocalISO(d))
    }
  }
  // hoje por último
  dias.push(dataLocalISO(hoje))

  let salvos = 0

  for (const dia of dias) {
    const since = Math.floor(inicioDiaUTC(dia).getTime() / 1000)
    const until = Math.floor(fimDiaUTC(dia).getTime() / 1000)
    const m = await insightsContaDia(token, igUserId, since, until)

    const ehHoje = dia === dataLocalISO(hoje)

    const linha: Record<string, unknown> = {
      cliente_id: clienteId,
      data: dia,
      coletado_em: new Date().toISOString(),
      alcance: m.alcance,
      visualizacoes: null,
      visitas_perfil: m.visitas_perfil,
      interacoes: m.interacoes,
      curtidas: m.curtidas,
      comentarios: m.comentarios,
      compartilhamentos: m.compartilhamentos,
      salvamentos: m.salvamentos,
      seguidores_ganhos: m.seguidores_ganhos,
      // hoje: snapshot atual; dias passados: null
      seguidores: ehHoje ? seguidores : null,
      media_count: ehHoje ? mediaCount : null
    }

    const { error } = await sbAdmin
      .from('conta_metricas_diarias')
      .upsert(linha, { onConflict: 'cliente_id,data' })
    if (error) {
      console.log(`conta_metricas_diarias erro dia=${dia}: ${error.message}`)
    } else {
      salvos++
    }
  }

  return salvos
}

serve(async (req) => {
  try {
    const cronSecret = Deno.env.get('METRICAS_CRON_SECRET') || ''
    const isCron =
      req.headers.get('x-cron-secret') === cronSecret && cronSecret.length > 0

    let clienteId: string | null = null

    if (isCron) {
      clienteId = Deno.env.get('IG_OWNER_ID') || null
    } else {
      const authHeader = req.headers.get('Authorization') || ''
      if (!authHeader.startsWith('Bearer ')) return resp(401, { error: 'Unauthorized' })
      const sbUrl = Deno.env.get('SUPABASE_URL')!
      const sbAnon = Deno.env.get('SUPABASE_ANON_KEY') || ''
      const sbUser = createClient(sbUrl, sbAnon, {
        global: { headers: { Authorization: authHeader } }
      })
      const { data: { user }, error } = await sbUser.auth.getUser()
      if (error || !user) return resp(401, { error: 'Unauthorized' })
      clienteId = user.id
    }

    if (!clienteId) return resp(400, { error: 'cliente_id missing' })

    const token = Deno.env.get('IG_ACCESS_TOKEN') || ''
    const igUserId = Deno.env.get('IG_USER_ID') || ''
    if (!token || !igUserId) return resp(500, { error: 'IG secrets not set' })

    const sbAdmin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    const body = req.method === 'POST' ? await req.json().catch(() => ({})) : {}
    const backfill = body?.backfill === true

    // A) Seguidores e media_count atuais
    const perfil = await igFetch(`/${igUserId}`, {
      fields: 'followers_count,media_count',
      access_token: token
    })
    const seguidores =
      typeof perfil?.followers_count === 'number' ? perfil.followers_count : null
    const mediaCount =
      typeof perfil?.media_count === 'number' ? perfil.media_count : null

    // B) Métricas diárias da conta
    const contaDias = await coletarContaDiario(
      token,
      igUserId,
      clienteId,
      sbAdmin,
      backfill,
      seguidores,
      mediaCount
    )

    // C) Posts/Reels
    const posts = await coletarPosts(token, igUserId, clienteId, sbAdmin)

    // D) Stories ativos
    const stories = await coletarStories(token, igUserId, clienteId, sbAdmin)

    console.log(
      `instagram-metricas ok: cliente=${clienteId} conta_dias=${contaDias} posts=${posts} stories=${stories}`
    )

    return resp(200, {
      ok: true,
      conta_dias: contaDias,
      posts,
      stories
    })
  } catch (e) {
    return resp(500, { error: String(e) })
  }
})
