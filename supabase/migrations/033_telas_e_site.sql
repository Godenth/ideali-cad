-- Ideali CAD · Migração 033 · Quais telas os cadistas usam e quais páginas do site são visitadas
-- App: soma os minutos de uso por TELA (só o nome da tela, ex.: "pedidos"), nunca o conteúdo.
-- Site: contagem agregada por dia, página e origem (google, instagram…). Sem IP, sem cookie, sem identificador.
-- Só o administrador lê os resumos.

-- 1) Tempo por tela, por cadista e por dia
create table if not exists public.uso_telas (
  user_id  uuid not null references auth.users(id) on delete cascade,
  dia      date not null,
  tela     text not null check (tela ~ '^[a-z0-9_]{1,20}$'),
  segundos integer not null default 0,
  primary key (user_id, dia, tela)
);
alter table public.uso_telas enable row level security;
revoke all on public.uso_telas from anon, authenticated;

-- Igual ao registrar_uso, e também anota em qual tela a pessoa estava
create or replace function public.registrar_uso_tela(seg integer default 0, disp text default null, tela text default null)
returns void language plpgsql security definer set search_path = public as $$
declare u uuid := auth.uid(); ult timestamptz; s integer; t text := lower(coalesce(tela, ''));
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
    if t ~ '^[a-z0-9_]{1,20}$' then
      insert into public.uso_telas (user_id, dia, tela, segundos)
      values (u, (now() at time zone 'America/Sao_Paulo')::date, t, s)
      on conflict (user_id, dia, tela) do update set segundos = uso_telas.segundos + excluded.segundos;
    end if;
  end if;
end $$;
revoke all on function public.registrar_uso_tela(integer, text, text) from public, anon;
grant execute on function public.registrar_uso_tela(integer, text, text) to authenticated;

-- Telas de um cadista (ou de todos, se alvo for nulo) nos últimos N dias — só administrador
create or replace function public.admin_telas(alvo uuid default null, dias integer default 30)
returns table (tela text, segundos bigint, usuarios bigint)
language plpgsql stable security definer set search_path = public as $$
declare hoje date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  if not public.admin_seguro() then raise exception 'Acesso restrito ao administrador' using errcode = '42501'; end if;
  return query
    select t.tela, sum(t.segundos)::bigint, count(distinct t.user_id)::bigint
      from public.uso_telas t
     where (alvo is null or t.user_id = alvo) and t.dia > hoje - greatest(1, least(coalesce(dias, 30), 365))
     group by t.tela order by 2 desc;
end $$;
revoke all on function public.admin_telas(uuid, integer) from public, anon;
grant execute on function public.admin_telas(uuid, integer) to authenticated;

-- Primeiros passos de cada cadista (datas), calculados do que já existe — só administrador
create or replace function public.admin_marcos()
returns table (user_id uuid, cadastro timestamptz, primeiro_cliente timestamptz, primeiro_pedido timestamptz,
               primeira_aprovacao timestamptz, primeiro_arquivo timestamptz, primeiro_pagamento timestamptz,
               voltou_7d boolean)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.admin_seguro() then raise exception 'Acesso restrito ao administrador' using errcode = '42501'; end if;
  return query
    select u.id, u.created_at,
      (select min(c.criado_em) from public.clientes c where c.user_id = u.id),
      (select min(p.criado_em) from public.pedidos p where p.user_id = u.id),
      (select min(p.aprovacao_desde)::timestamptz from public.pedidos p where p.user_id = u.id and p.aprovacao_desde is not null),
      (select min(a.criado_em) from public.arquivos a where a.user_id = u.id),
      (select min(g.criado_em) from public.pagamentos g where g.user_id = u.id),
      exists (select 1 from public.uso_diario d where d.user_id = u.id and d.dia >= (u.created_at at time zone 'America/Sao_Paulo')::date + 7 and d.segundos >= 60)
    from auth.users u;
end $$;
revoke all on function public.admin_marcos() from public, anon;
grant execute on function public.admin_marcos() to authenticated;

-- 2) Site público: visitas agregadas (sem nenhum dado pessoal)
create table if not exists public.site_visitas (
  dia     date not null,
  pagina  text not null check (pagina ~ '^[a-z0-9_]{1,20}$'),
  origem  text not null check (origem ~ '^[a-z0-9_]{1,20}$'),
  visitas integer not null default 0,
  primary key (dia, pagina, origem)
);
alter table public.site_visitas enable row level security;
revoke all on public.site_visitas from anon, authenticated;

create or replace function public.registrar_visita(pagina text, origem text default 'direto')
returns void language plpgsql security definer set search_path = public as $$
declare p text := lower(coalesce(pagina, '')); o text := lower(coalesce(origem, 'direto'));
begin
  if p !~ '^(inicio|tour|precos|privacidade|termos|rede|app|cadastro|captura)$' then return; end if;
  if o !~ '^[a-z0-9_]{1,20}$' then o := 'outro'; end if;
  insert into public.site_visitas (dia, pagina, origem, visitas)
  values ((now() at time zone 'America/Sao_Paulo')::date, p, o, 1)
  on conflict (dia, pagina, origem) do update set visitas = least(site_visitas.visitas + 1, 1000000);
end $$;
revoke all on function public.registrar_visita(text, text) from public;
grant execute on function public.registrar_visita(text, text) to anon, authenticated;

create or replace function public.admin_site(dias integer default 30)
returns table (dia date, pagina text, origem text, visitas bigint)
language plpgsql stable security definer set search_path = public as $$
declare hoje date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  if not public.admin_seguro() then raise exception 'Acesso restrito ao administrador' using errcode = '42501'; end if;
  return query
    select v.dia, v.pagina, v.origem, v.visitas::bigint from public.site_visitas v
     where v.dia > hoje - greatest(1, least(coalesce(dias, 30), 365)) order by v.dia;
end $$;
revoke all on function public.admin_site(integer) from public, anon;
grant execute on function public.admin_site(integer) to authenticated;
