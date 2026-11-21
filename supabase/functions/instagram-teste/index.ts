import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })

  try {
    const token = Deno.env.get('IG_ACCESS_TOKEN')
    const userId = Deno.env.get('IG_USER_ID')

    if (!token || !userId) {
      return new Response(
        JSON.stringify({ error: 'Secrets IG_ACCESS_TOKEN e IG_USER_ID não configurados' }),
        { status: 500, headers: { ...CORS, 'Content-Type': 'application/json' } }
      )
    }

    const url =
      `https://graph.facebook.com/v27.0/${userId}` +
      `?fields=id,username,name,profile_picture_url,followers_count,media_count` +
      `&access_token=${token}`

    const res = await fetch(url)
    const data = await res.json()

    // Nunca expor o token na resposta
    if (data.access_token) delete data.access_token

    if (!res.ok) {
      return new Response(
        JSON.stringify({ error: data.error?.message || 'Erro na API do Instagram', code: data.error?.code }),
        { status: 502, headers: { ...CORS, 'Content-Type': 'application/json' } }
      )
    }

    return new Response(JSON.stringify(data), {
      headers: { ...CORS, 'Content-Type': 'application/json' },
    })
  } catch (e) {
    return new Response(
      JSON.stringify({ error: 'Erro interno' }),
      { status: 500, headers: { ...CORS, 'Content-Type': 'application/json' } }
    )
  }
})
