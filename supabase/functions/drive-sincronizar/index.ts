// drive-sincronizar — sincroniza pastas do Google Drive para mkt_temas / mkt_tema_midias.
// Chamado por cron (x-cron-secret) processa todos os clientes; chamado pelo usuário
// (Authorization Bearer) processa só o próprio cliente.
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { mikaVisao } from '../_shared/mika-ia.ts'

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}
const ESCOPO_DRIVE = 'https://www.googleapis.com/auth/drive.readonly'
const PAINEL_VISAO = 'Descreva em até 2 frases o que aparece nesta imagem, em português. Seja objetivo.'

const jsonResp = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
  })

function b64url(input: ArrayBuffer | Uint8Array): string {
  const bytes = input instanceof Uint8Array ? input : new Uint8Array(input)
  let bin = ''
  for (const b of bytes) bin += String.fromCharCode(b)
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

// JWT RS256 manual (sem libs) para a Service Account do Google
async function googleAccessToken(): Promise<string> {
  const raw = Deno.env.get('GOOGLE_SERVICE_ACCOUNT_JSON')
  if (!raw) throw new Error('GOOGLE_SERVICE_ACCOUNT_JSON não configurado')
  const conta = JSON.parse(raw) as { client_email: string; private_key: string }
  const agora = Math.floor(Date.now() / 1000)
  const header = b64url(new TextEncoder().encode(JSON.stringify({ alg: 'RS256', typ: 'JWT' })))
  const payload = b64url(new TextEncoder().encode(JSON.stringify({
    iss: conta.client_email,
    scope: ESCOPO_DRIVE,
    aud: 'https://oauth2.googleapis.com/token',
    exp: agora + 3600,
    iat: agora,
  })))
  const assinatura = `${header}.${payload}`
  const corpo = conta.private_key
    .replace(/\\n/g, '\n')
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace(/\s+/g, '')
  const der = Uint8Array.from(atob(corpo), (c) => c.charCodeAt(0))
  const chave = await crypto.subtle.importKey(
    'pkcs8',
    der,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  )
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', chave, new TextEncoder().encode(assinatura))
  const jwt = `${assinatura}.${b64url(sig)}`
  const r = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }).toString(),
  })
  if (!r.ok) throw new Error(`Google token ${r.status}`)
  const d = await r.json() as { access_token?: string }
  if (!d.access_token) throw new Error('Google não devolveu access_token')
  return d.access_token
}

type DriveFile = { id: string; name: string; mimeType: string; modifiedTime?: string }

async function driveLista(token: string, q: string): Promise<DriveFile[]> {
  const saida: DriveFile[] = []
  let pageToken = ''
  do {
    const params = new URLSearchParams({
      q,
      fields: 'nextPageToken,files(id,name,mimeType,modifiedTime)',
      pageSize: '100',
      supportsAllDrives: 'true',
      includeItemsFromAllDrives: 'true',
    })
    if (pageToken) params.set('pageToken', pageToken)
    const r = await fetch(`https://www.googleapis.com/drive/v3/files?${params}`, {
      headers: { Authorization: `Bearer ${token}` },
    })
    if (!r.ok) throw new Error(`Drive list ${r.status}`)
    const d = await r.json() as { files?: DriveFile[]; nextPageToken?: string }
    saida.push(...(d.files ?? []))
    pageToken = d.nextPageToken ?? ''
  } while (pageToken)
  return saida
}

async function driveBaixar(token: string, fileId: string): Promise<{ dados: ArrayBuffer; contentType: string }> {
  const r = await fetch(
    `https://www.googleapis.com/drive/v3/files/${fileId}?alt=media&supportsAllDrives=true`,
    { headers: { Authorization: `Bearer ${token}` } },
  )
  if (!r.ok) throw new Error(`Drive download ${r.status}`)
  return {
    dados: await r.arrayBuffer(),
    contentType: r.headers.get('content-type') ?? 'application/octet-stream',
  }
}

async function driveExportarTexto(token: string, fileId: string): Promise<string> {
  const r = await fetch(
    `https://www.googleapis.com/drive/v3/files/${fileId}/export?mimeType=text/plain`,
    { headers: { Authorization: `Bearer ${token}` } },
  )
  if (!r.ok) throw new Error(`Drive export ${r.status}`)
  return await r.text()
}

function extensao(nome: string): string {
  const p = nome.split('.')
  return p.length > 1 ? p.pop()!.toLowerCase() : ''
}

function tipoDe(mimeType: string): 'imagem' | 'video' | 'texto' | null {
  if (mimeType.startsWith('image/')) return 'imagem'
  if (mimeType.startsWith('video/')) return 'video'
  if (
    mimeType === 'application/vnd.google-apps.document' ||
    mimeType === 'text/plain' ||
    mimeType === 'text/markdown'
  ) return 'texto'
  return null
}

async function upsertMidia(
  sb: ReturnType<typeof createClient>,
  temaId: string,
  arquivo: DriveFile,
  campos: { arquivo_url?: string | null; descricao?: string | null },
): Promise<void> {
  const { error } = await sb.from('mkt_tema_midias').upsert({
    tema_id: temaId,
    drive_file_id: arquivo.id,
    modified_time: arquivo.modifiedTime ?? null,
    tipo: tipoDe(arquivo.mimeType) ?? 'texto',
    arquivo_url: campos.arquivo_url ?? null,
    descricao: campos.descricao ?? null,
    ativo: true,
  }, { onConflict: 'tema_id,drive_file_id' })
  if (error) throw new Error(`mkt_tema_midias: ${error.message}`)
}

async function processarTema(
  sb: ReturnType<typeof createClient>,
  sbUrl: string,
  clienteId: string,
  temaId: string,
  pastaId: string,
  token: string,
): Promise<number> {
  const arquivos = await driveLista(token, `'${pastaId}' in parents and trashed=false`)
  const textos: string[] = []
  const vistos = new Set<string>()
  let midias = 0

  for (const arq of arquivos) {
    const tipo = tipoDe(arq.mimeType)
    if (!tipo) continue
    vistos.add(arq.id)

    if (tipo === 'texto') {
      const conteudo = arq.mimeType === 'application/vnd.google-apps.document'
        ? await driveExportarTexto(token, arq.id)
        : new TextDecoder().decode(await driveBaixar(token, arq.id).then((x) => x.dados))
      textos.push(conteudo)
      await upsertMidia(sb, temaId, arq, {})
    } else if (tipo === 'video') {
      await upsertMidia(sb, temaId, arq, {})
    } else {
      const { data: existente } = await sb
        .from('mkt_tema_midias')
        .select('modified_time')
        .eq('tema_id', temaId)
        .eq('drive_file_id', arq.id)
        .maybeSingle()
      if (existente && existente.modified_time === (arq.modifiedTime ?? null)) continue

      const { dados, contentType } = await driveBaixar(token, arq.id)
      const ext = extensao(arq.name) || 'png'
      const path = `${clienteId}/temas/${temaId}/${arq.id}.${ext}`
      const { error: upErr } = await sb.storage.from('marketing').upload(path, dados, {
        contentType,
        upsert: true,
      })
      if (upErr) throw new Error(`upload: ${upErr.message}`)
      const url = `${sbUrl}/storage/v1/object/public/marketing/${path}`

      let descricao: string | null = null
      try {
        descricao = await mikaVisao(url, PAINEL_VISAO)
      } catch {
        descricao = null
      }
      await upsertMidia(sb, temaId, arq, { arquivo_url: url, descricao })
    }
    midias++
  }

  if (textos.length) {
    const { error } = await sb
      .from('mkt_temas')
      .update({ texto_base: textos.join('\n---\n'), sincronizado_em: new Date().toISOString() })
      .eq('id', temaId)
    if (error) throw new Error(`mkt_temas texto_base: ${error.message}`)
  }

  const { data: antigas } = await sb
    .from('mkt_tema_midias')
    .select('id,drive_file_id')
    .eq('tema_id', temaId)
  for (const m of antigas ?? []) {
    if (!vistos.has(m.drive_file_id)) {
      await sb.from('mkt_tema_midias').update({ ativo: false }).eq('id', m.id)
    }
  }

  return midias
}

async function processarCliente(
  sb: ReturnType<typeof createClient>,
  sbUrl: string,
  clienteId: string,
  driveFolderId: string,
  token: string,
): Promise<{ temas: number; midias: number }> {
  const pastas = await driveLista(
    token,
    `'${driveFolderId}' in parents and mimeType='application/vnd.google-apps.folder' and trashed=false`,
  )
  const vistas = new Set<string>()
  let temas = 0
  let midias = 0

  for (const pasta of pastas) {
    vistas.add(pasta.id)
    const { data: tema } = await sb
      .from('mkt_temas')
      .select('id')
      .eq('cliente_id', clienteId)
      .eq('drive_folder_id', pasta.id)
      .maybeSingle()

    let temaId: string
    if (tema) {
      const { error } = await sb.from('mkt_temas').update({
        nome: pasta.name,
        ativo: true,
        sincronizado_em: new Date().toISOString(),
      }).eq('id', tema.id)
      if (error) throw new Error(`mkt_temas update: ${error.message}`)
      temaId = tema.id
    } else {
      const { data: criado, error } = await sb.from('mkt_temas').insert({
        cliente_id: clienteId,
        nome: pasta.name,
        drive_folder_id: pasta.id,
        ativo: true,
        sincronizado_em: new Date().toISOString(),
      }).select('id').single()
      if (error) throw new Error(`mkt_temas insert: ${error.message}`)
      temaId = criado!.id
    }
    temas++
    midias += await processarTema(sb, sbUrl, clienteId, temaId, pasta.id, token)
  }

  const { data: temasAntigos } = await sb
    .from('mkt_temas')
    .select('id,drive_folder_id')
    .eq('cliente_id', clienteId)
  for (const t of temasAntigos ?? []) {
    if (t.drive_folder_id && !vistas.has(t.drive_folder_id)) {
      await sb.from('mkt_temas').update({ ativo: false }).eq('id', t.id)
    }
  }

  return { temas, midias }
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })
  if (req.method !== 'POST') return jsonResp(405, { error: 'Método não permitido' })

  const sbUrl = Deno.env.get('SUPABASE_URL')!
  const sbServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  const sb = createClient(sbUrl, sbServiceKey)

  const auth = req.headers.get('authorization') ?? ''
  const tokenUsuario = auth.startsWith('Bearer ') ? auth.slice(7).trim() : ''
  const cronSecret = Deno.env.get('CRON_SECRET')
  const incomingCron = req.headers.get('x-cron-secret')

  let todos = false
  let clienteId: string | null = null

  if (cronSecret && incomingCron && incomingCron === cronSecret) {
    todos = true
  } else if (tokenUsuario) {
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
  } else {
    return jsonResp(401, { error: 'Não autorizado' })
  }

  let perfis: Array<{ cliente_id: string; drive_folder_id: string | null }> = []
  try {
    let q = sb.from('mkt_perfil_marca').select('cliente_id, drive_folder_id').not('drive_folder_id', 'is', null)
    if (!todos) q = q.eq('cliente_id', clienteId!)
    const { data, error } = await q
    if (error) throw error
    perfis = data ?? []
  } catch {
    return jsonResp(200, {
      ok: true,
      temas: 0,
      midias: 0,
      aviso: 'campo drive_folder_id não existe em mkt_perfil_marca',
    })
  }

  try {
    const token = await googleAccessToken()
    let temas = 0
    let midias = 0
    for (const p of perfis) {
      if (!p.drive_folder_id) continue
      try {
        const r = await processarCliente(sb, sbUrl, p.cliente_id, p.drive_folder_id, token)
        temas += r.temas
        midias += r.midias
      } catch {
        // segue para o próximo cliente
      }
    }
    return jsonResp(200, { ok: true, temas, midias })
  } catch (e) {
    return jsonResp(502, { ok: false, error: e instanceof Error ? e.message : 'Erro ao sincronizar' })
  }
})
