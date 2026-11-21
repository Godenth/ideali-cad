import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

serve(async (req) => {
  // Autenticação via secret de cron
  const cronSecret = Deno.env.get('CRON_SECRET')
  const incomingSecret = req.headers.get('x-cron-secret')
  if (!cronSecret || incomingSecret !== cronSecret) {
    return new Response('Unauthorized', { status: 401 })
  }

  const sbUrl = Deno.env.get('SUPABASE_URL')!
  const sbServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  const sb = createClient(sbUrl, sbServiceKey)

  // Buscar posts aprovados com agendado_para <= agora
  const { data: posts, error } = await sb
    .from('posts_agendados')
    .select('id')
    .eq('status', 'aprovado')
    .lte('agendado_para', new Date().toISOString())
    .limit(10)

  if (error || !posts || posts.length === 0) {
    return new Response(JSON.stringify({ processados: 0, erro: error?.message }), {
      headers: { 'Content-Type': 'application/json' },
    })
  }

  let ok = 0, errs = 0
  for (const post of posts) {
    try {
      const r = await fetch(`${sbUrl}/functions/v1/instagram-publicar`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${sbServiceKey}`,
        },
        body: JSON.stringify({ post_id: post.id }),
      })
      if (r.ok) { ok++ } else { errs++ }
    } catch {
      errs++
    }
  }

  return new Response(JSON.stringify({ processados: posts.length, publicados: ok, erros: errs }), {
    headers: { 'Content-Type': 'application/json' },
  })
})
