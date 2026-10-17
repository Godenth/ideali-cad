// Ideali CAD · Clima do dia (fonte: MET Norway, licença CC BY 4.0 — uso comercial permitido com crédito).
// Roda no servidor para identificar o app perante a MET Norway e guardar em cache.
const UA = "IdealiCAD/1.0 (+https://idealisystems.com/)";
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

type Resp = { temp: number; simbolo: string; min: number; max: number; atualizado: string; fonte: string };
const cache = new Map<string, { exp: number; data: Resp }>();

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json(405, { erro: "Método não permitido" });

  const body = await req.json().catch(() => ({}));
  const lat = Number(body?.lat), lon = Number(body?.lon);
  // Só Brasil (com folga), para evitar uso indevido.
  if (!Number.isFinite(lat) || !Number.isFinite(lon) || lat < -35 || lat > 7 || lon < -75 || lon > -28) {
    return json(400, { erro: "Coordenadas inválidas" });
  }
  const la = lat.toFixed(2), lo = lon.toFixed(2), chave = `${la},${lo}`;
  const c = cache.get(chave);
  if (c && c.exp > Date.now()) return json(200, c.data);

  const r = await fetch(`https://api.met.no/weatherapi/locationforecast/2.0/compact?lat=${la}&lon=${lo}`, {
    headers: { "User-Agent": UA, "Accept-Encoding": "gzip" },
  });
  if (!r.ok) return json(502, { erro: "Serviço de clima indisponível" });
  const j = await r.json();
  const ts = j?.properties?.timeseries ?? [];
  if (!ts.length) return json(502, { erro: "Sem previsão" });

  const agora = ts[0];
  const simbolo = agora.data?.next_1_hours?.summary?.symbol_code ?? agora.data?.next_6_hours?.summary?.symbol_code ?? "cloudy";
  const limite = Date.parse(agora.time) + 24 * 3600 * 1000;
  const temps = ts.filter((t: any) => Date.parse(t.time) <= limite).map((t: any) => t.data.instant.details.air_temperature);
  const data: Resp = {
    temp: agora.data.instant.details.air_temperature,
    simbolo,
    min: Math.min(...temps),
    max: Math.max(...temps),
    atualizado: j.properties.meta?.updated_at ?? new Date().toISOString(),
    fonte: "MET Norway",
  };
  const expira = Date.parse(r.headers.get("Expires") ?? "") || Date.now() + 30 * 60 * 1000;
  cache.set(chave, { exp: Math.max(expira, Date.now() + 10 * 60 * 1000), data });
  return json(200, data);
});
