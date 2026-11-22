import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })

  const token = Deno.env.get('IG_ACCESS_TOKEN')!
  const igUserId = Deno.env.get('IG_USER_ID')!
  const sbUrl = Deno.env.get('SUPABASE_URL')!
  const sbServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

  // Admin client (bypassa RLS para buscar e atualizar o post)
  const sb = createClient(sbUrl, sbServiceKey)

  try {
    const body = await req.json()
    const postId = body.post_id
    if (!postId) return new Response(JSON.stringify({ error: 'post_id obrigatório' }), { status: 400, headers: { ...CORS, 'Content-Type': 'application/json' } })

    // 1. Buscar post
    const { data: post, error: fetchErr } = await sb
      .from('posts_agendados')
      .select('*')
      .eq('id', postId)
      .single()
    if (fetchErr || !post) return new Response(JSON.stringify({ error: 'Post não encontrado' }), { status: 404, headers: { ...CORS, 'Content-Type': 'application/json' } })

    // 2. Marcar como publicando
    await sb.from('posts_agendados').update({ status: 'publicando' }).eq('id', postId)

    // 3. Verificar limite de publicação do dia
    const limitRes = await fetch(
      `https://graph.facebook.com/v27.0/${igUserId}/content_publishing_limit?fields=config,quota_usage&access_token=${token}`
    )
    const limitData = await limitRes.json()
    const quota = limitData?.data?.[0]
    if (quota && quota.quota_usage >= (quota.config?.quota_total ?? 50)) {
      await sb.from('posts_agendados').update({ status: 'erro', erro: 'Limite diário de publicações do Instagram atingido' }).eq('id', postId)
      return new Response(JSON.stringify({ error: 'Limite diário atingido' }), { status: 429, headers: { ...CORS, 'Content-Type': 'application/json' } })
    }

    // 3b. Carrossel: cria os containers filhos e depois o container principal
    if (post.tipo === 'carrossel') {
      const slides: Array<{ png_path?: string }> = Array.isArray(post.slides) ? post.slides.slice(0, 10) : []
      if (!slides.length) {
        await sb.from('posts_agendados').update({ status: 'erro', erro: 'Carrossel sem slides' }).eq('id', postId)
        return new Response(JSON.stringify({ error: 'Carrossel sem slides' }), { status: 400, headers: { ...CORS, 'Content-Type': 'application/json' } })
      }

      const esperarPronto = async (id: string, maxMs: number) => {
        const t0 = Date.now()
        let status = 'IN_PROGRESS'
        while (status === 'IN_PROGRESS' || status === 'PUBLISHED') {
          if (Date.now() - t0 > maxMs) return 'TIMEOUT'
          await new Promise(r => setTimeout(r, 3000))
          const stRes = await fetch(`https://graph.facebook.com/v27.0/${id}?fields=status_code&access_token=${token}`)
          const stData = await stRes.json()
          status = stData.status_code ?? 'ERROR'
          if (status === 'ERROR' || status === 'EXPIRED') return status
        }
        return status
      }

      const childIds: string[] = []
      for (const slide of slides) {
        if (!slide.png_path) continue
        const slideUrl = sbUrl + '/storage/v1/object/public/marketing/' + slide.png_path
        const childRes = await fetch(
          `https://graph.facebook.com/v27.0/${igUserId}/media`,
          { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams({ image_url: slideUrl, is_carousel_item: 'true', access_token: token }).toString() }
        )
        const childData = await childRes.json()
        if (!childRes.ok || !childData.id) {
          const msg = childData.error?.message || 'Falha ao criar slide do carrossel'
          await sb.from('posts_agendados').update({ status: 'erro', erro: msg }).eq('id', postId)
          return new Response(JSON.stringify({ error: msg }), { status: 502, headers: { ...CORS, 'Content-Type': 'application/json' } })
        }
        const childStatus = await esperarPronto(childData.id, 60000)
        if (childStatus !== 'FINISHED') {
          const msg = childStatus === 'TIMEOUT' ? 'Timeout: slide do carrossel não ficou pronto em 60s' : `Slide do carrossel ${childStatus}`
          await sb.from('posts_agendados').update({ status: 'erro', erro: msg }).eq('id', postId)
          return new Response(JSON.stringify({ error: msg }), { status: childStatus === 'TIMEOUT' ? 504 : 502, headers: { ...CORS, 'Content-Type': 'application/json' } })
        }
        childIds.push(childData.id)
      }

      if (!childIds.length) {
        await sb.from('posts_agendados').update({ status: 'erro', erro: 'Carrossel sem slides válidos' }).eq('id', postId)
        return new Response(JSON.stringify({ error: 'Carrossel sem slides válidos' }), { status: 400, headers: { ...CORS, 'Content-Type': 'application/json' } })
      }

      const caption = [post.legenda, post.hashtags].filter(Boolean).join('\n')
      const mainRes = await fetch(
        `https://graph.facebook.com/v27.0/${igUserId}/media`,
        { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams({ media_type: 'CAROUSEL', children: childIds.join(','), caption, access_token: token }).toString() }
      )
      const mainData = await mainRes.json()
      if (!mainRes.ok || !mainData.id) {
        const msg = mainData.error?.message || 'Falha ao criar container do carrossel'
        await sb.from('posts_agendados').update({ status: 'erro', erro: msg }).eq('id', postId)
        return new Response(JSON.stringify({ error: msg }), { status: 502, headers: { ...CORS, 'Content-Type': 'application/json' } })
      }

      const containerId = mainData.id
      await sb.from('posts_agendados').update({ ig_container_id: containerId }).eq('id', postId)

      const mainStatus = await esperarPronto(containerId, 90000)
      if (mainStatus !== 'FINISHED') {
        const msg = mainStatus === 'TIMEOUT' ? 'Timeout: container do carrossel não ficou pronto em 90s' : `Container do carrossel ${mainStatus}`
        await sb.from('posts_agendados').update({ status: 'erro', erro: msg }).eq('id', postId)
        return new Response(JSON.stringify({ error: msg }), { status: mainStatus === 'TIMEOUT' ? 504 : 502, headers: { ...CORS, 'Content-Type': 'application/json' } })
      }

      const pubRes = await fetch(
        `https://graph.facebook.com/v27.0/${igUserId}/media_publish`,
        { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams({ creation_id: containerId, access_token: token }).toString() }
      )
      const pubData = await pubRes.json()
      if (!pubRes.ok || !pubData.id) {
        const msg = pubData.error?.message || 'Falha ao publicar'
        await sb.from('posts_agendados').update({ status: 'erro', erro: msg }).eq('id', postId)
        return new Response(JSON.stringify({ error: msg }), { status: 502, headers: { ...CORS, 'Content-Type': 'application/json' } })
      }

      await sb.from('posts_agendados').update({ status: 'publicado', ig_media_id: pubData.id, erro: null }).eq('id', postId)
      return new Response(JSON.stringify({ ok: true, ig_media_id: pubData.id }), { headers: { ...CORS, 'Content-Type': 'application/json' } })
    }

    // 4. Criar container na Graph API
    const isVideo = post.tipo === 'reel' || (post.midia_url && (post.midia_url.includes('.mp4') || post.midia_url.includes('.mov')))
    const caption = [post.legenda, post.hashtags].filter(Boolean).join('\n')

    let containerParams: Record<string, string> = { access_token: token }
    if (post.tipo === 'story') {
      containerParams = isVideo
        ? { media_type: 'STORIES', video_url: post.midia_url, access_token: token }
        : { media_type: 'STORIES', image_url: post.midia_url, access_token: token }
    } else if (post.tipo === 'reel') {
      containerParams = { media_type: 'REELS', video_url: post.midia_url, caption, access_token: token }
    } else {
      // feed
      containerParams = isVideo
        ? { media_type: 'VIDEO', video_url: post.midia_url, caption, access_token: token }
        : { image_url: post.midia_url, caption, access_token: token }
    }

    const containerRes = await fetch(
      `https://graph.facebook.com/v27.0/${igUserId}/media`,
      { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams(containerParams).toString() }
    )
    const containerData = await containerRes.json()

    if (!containerRes.ok || !containerData.id) {
      const msg = containerData.error?.message || 'Falha ao criar container'
      await sb.from('posts_agendados').update({ status: 'erro', erro: msg }).eq('id', postId)
      return new Response(JSON.stringify({ error: msg }), { status: 502, headers: { ...CORS, 'Content-Type': 'application/json' } })
    }

    const containerId = containerData.id
    await sb.from('posts_agendados').update({ ig_container_id: containerId }).eq('id', postId)

    // 5. Aguardar container FINISHED (máx 90s, poll a cada 3s)
    const startTime = Date.now()
    let statusCode = 'IN_PROGRESS'
    while (statusCode === 'IN_PROGRESS' || statusCode === 'PUBLISHED') {
      if (Date.now() - startTime > 90000) {
        await sb.from('posts_agendados').update({ status: 'erro', erro: 'Timeout: container não ficou pronto em 90s' }).eq('id', postId)
        return new Response(JSON.stringify({ error: 'Timeout' }), { status: 504, headers: { ...CORS, 'Content-Type': 'application/json' } })
      }
      await new Promise(r => setTimeout(r, 3000))
      const stRes = await fetch(`https://graph.facebook.com/v27.0/${containerId}?fields=status_code&access_token=${token}`)
      const stData = await stRes.json()
      statusCode = stData.status_code ?? 'ERROR'
      if (statusCode === 'ERROR' || statusCode === 'EXPIRED') {
        const msg = `Container ${statusCode}`
        await sb.from('posts_agendados').update({ status: 'erro', erro: msg }).eq('id', postId)
        return new Response(JSON.stringify({ error: msg }), { status: 502, headers: { ...CORS, 'Content-Type': 'application/json' } })
      }
    }

    // 6. Publicar
    const pubRes = await fetch(
      `https://graph.facebook.com/v27.0/${igUserId}/media_publish`,
      { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams({ creation_id: containerId, access_token: token }).toString() }
    )
    const pubData = await pubRes.json()

    if (!pubRes.ok || !pubData.id) {
      const msg = pubData.error?.message || 'Falha ao publicar'
      await sb.from('posts_agendados').update({ status: 'erro', erro: msg }).eq('id', postId)
      return new Response(JSON.stringify({ error: msg }), { status: 502, headers: { ...CORS, 'Content-Type': 'application/json' } })
    }

    // 7. Salvar resultado
    await sb.from('posts_agendados').update({ status: 'publicado', ig_media_id: pubData.id, erro: null }).eq('id', postId)
    return new Response(JSON.stringify({ ok: true, ig_media_id: pubData.id }), { headers: { ...CORS, 'Content-Type': 'application/json' } })

  } catch (e) {
    return new Response(JSON.stringify({ error: 'Erro interno' }), { status: 500, headers: { ...CORS, 'Content-Type': 'application/json' } })
  }
})
