-- =====================================================================
-- Ideali CAD · Migração 017 · Uso do sistema para o painel do administrador
-- Guarda só QUANTO TEMPO cada cadista usa o sistema por dia e QUANDO foi
-- visto pela última vez (para "online agora"). Não guarda páginas, cliques,
-- IP nem localização: a cidade/UF vêm do perfil que o próprio cadista preenche.
-- O administrador vê só contagens (pedidos, clientes), nunca o conteúdo deles.
-- Ao excluir a conta, tudo some junto (on delete cascade).
-- =====================================================================

create table if not exists public.uso_diario (
  user_id  uuid not null references auth.users(id) on delete cascade,
  dia      date not null,
  segundos integer not null default 0,
  primary key (user_id, dia)
);
alter table public.uso_diario enable row level security;
revoke all on public.uso_diario from anon, authenticated;

create table if not exists public.presenca (
  user_id     uuid primary key references auth.users(id) on delete cascade,
  visto_em    timestamptz not null default now(),
  dispositivo text
);
alter table public.presenca enable row level security;
revoke all on public.presenca from anon, authenticated;

-- Chamado pelo app a cada minuto enquanto a aba está aberta e a pessoa está mexendo.
-- Soma no máximo 90 s por chamada e ignora chamadas a menos de 40 s da anterior,
-- para o tempo não inflar se o app chamar várias vezes.
create or replace function public.registrar_uso(seg integer default 0, disp text default null)
returns void language plpgsql security definer set search_path = public as $$
declare u uuid := auth.uid(); ult timestamptz; s integer;
begin
  if u is null then return; end if;
  select visto_em into ult from public.presenca where user_id = u;
  s := greatest(0, least(coalesce(seg, 0), 90));
  if ult is not null and ult > now() - interval '40 seconds' then s := 0; end if;
  insert into public.presenca (user_id, visto_em, dispositivo)
  values (u, now(), left(disp, 20))
  on conflict (user_id) do update set visto_em = excluded.visto_em, dispositivo = coalesce(excluded.dispositivo, presenca.dispositivo);
  if s > 0 then
    insert into public.uso_diario (user_id, dia, segundos)
    values (u, (now() at time zone 'America/Sao_Paulo')::date, s)
    on conflict (user_id, dia) do update set segundos = uso_diario.segundos + excluded.segundos;
  end if;
end $$;
revoke all on function public.registrar_uso(integer, text) from public, anon;
grant execute on function public.registrar_uso(integer, text) to authenticated;

-- Métricas por cadista (só administrador). Apenas números agregados.
create or replace function public.admin_metricas()
returns table (
  user_id uuid, visto_em timestamptz, dispositivo text,
  seg_hoje bigint, seg_7d bigint, seg_30d bigint, seg_total bigint, dias_ativos_30 bigint,
  pedidos_total bigint, pedidos_30d bigint, clientes_total bigint,
  cidade text, uf text
)
language plpgsql stable security definer set search_path = public as $$
declare hoje date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  if not public.sou_admin() then
    raise exception 'Acesso restrito ao administrador' using errcode = '42501';
  end if;
  return query
    select u.id, pr.visto_em, pr.dispositivo,
      coalesce((select sum(d.segundos) from public.uso_diario d where d.user_id = u.id and d.dia = hoje), 0)::bigint,
      coalesce((select sum(d.segundos) from public.uso_diario d where d.user_id = u.id and d.dia > hoje - 7), 0)::bigint,
      coalesce((select sum(d.segundos) from public.uso_diario d where d.user_id = u.id and d.dia > hoje - 30), 0)::bigint,
      coalesce((select sum(d.segundos) from public.uso_diario d where d.user_id = u.id), 0)::bigint,
      (select count(*) from public.uso_diario d where d.user_id = u.id and d.dia > hoje - 30 and d.segundos >= 60)::bigint,
      (select count(*) from public.pedidos p where p.user_id = u.id and p.deleted_at is null)::bigint,
      (select count(*) from public.pedidos p where p.user_id = u.id and p.deleted_at is null and p.recebido_em > hoje - 30)::bigint,
      (select count(*) from public.clientes c where c.user_id = u.id and c.deleted_at is null)::bigint,
      pf.cidade, pf.uf
    from auth.users u
    left join public.presenca pr on pr.user_id = u.id
    left join public.perfis pf on pf.user_id = u.id;
end $$;
revoke all on function public.admin_metricas() from public, anon;
grant execute on function public.admin_metricas() to authenticated;
