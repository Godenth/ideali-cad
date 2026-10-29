-- Ideali CAD · Migração 034 · Painel do dono: contagem de recursos e agentes usados + conserto da contagem de telas
-- Guarda só "cadista X usou o recurso Y N vezes no dia" (ex.: "cobranca", "ag_ven"). Nunca o conteúdo.
-- Só o administrador lê os resumos.

-- 1) Conserto: o parâmetro "tela" tinha o mesmo nome da coluna e o ON CONFLICT dava erro de ambiguidade,
--    então nenhuma tela era registrada. A diretiva abaixo faz o banco usar a coluna nesses casos.
create or replace function public.registrar_uso_tela(seg integer default 0, disp text default null, tela text default null)
returns void language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare u uuid := auth.uid(); ult timestamptz; s integer; t text := lower(coalesce(registrar_uso_tela.tela, ''));
begin
  if u is null then return; end if;
  select p.visto_em into ult from public.presenca p where p.user_id = u;
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

-- 2) Recursos usados, por cadista e por dia
create table if not exists public.uso_recursos (
  user_id uuid not null references auth.users(id) on delete cascade,
  dia     date not null,
  recurso text not null check (recurso ~ '^[a-z0-9_]{1,24}$'),
  vezes   integer not null default 0,
  primary key (user_id, dia, recurso)
);
alter table public.uso_recursos enable row level security;
revoke all on public.uso_recursos from anon, authenticated;

-- Recebe um pacote {"cobranca":2,"ag_ven":1}. Cada recurso conta no máximo 50 por envio e 500 por dia.
create or replace function public.registrar_recursos(itens jsonb)
returns void language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare u uuid := auth.uid(); k text; v integer; hoje date := (now() at time zone 'America/Sao_Paulo')::date; n integer := 0;
begin
  if u is null or itens is null or jsonb_typeof(itens) <> 'object' then return; end if;
  for k, v in select key, least(greatest(coalesce((value #>> '{}')::integer, 0), 0), 50) from jsonb_each(itens) loop
    n := n + 1; exit when n > 40;
    if v > 0 and k ~ '^[a-z0-9_]{1,24}$' then
      insert into public.uso_recursos (user_id, dia, recurso, vezes) values (u, hoje, k, v)
      on conflict (user_id, dia, recurso) do update set vezes = least(uso_recursos.vezes + excluded.vezes, 500);
    end if;
  end loop;
exception when others then return;
end $$;
revoke all on function public.registrar_recursos(jsonb) from public, anon;
grant execute on function public.registrar_recursos(jsonb) to authenticated;

-- Resumo dos recursos (de um cadista ou de todos) — só administrador
create or replace function public.admin_recursos(alvo uuid default null, dias integer default 30)
returns table (recurso text, vezes bigint, usuarios bigint)
language plpgsql stable security definer set search_path = public as $$
declare hoje date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  if not public.admin_seguro() then raise exception 'Acesso restrito ao administrador' using errcode = '42501'; end if;
  return query
    select r.recurso, sum(r.vezes)::bigint, count(distinct r.user_id)::bigint
      from public.uso_recursos r
     where (alvo is null or r.user_id = alvo) and r.dia > hoje - greatest(1, least(coalesce(dias, 30), 365))
     group by r.recurso order by 2 desc;
end $$;
revoke all on function public.admin_recursos(uuid, integer) from public, anon;
grant execute on function public.admin_recursos(uuid, integer) to authenticated;

-- Atividade por dia (pessoas ativas e minutos) para o gráfico do painel — só administrador
create or replace function public.admin_ativos_dia(dias integer default 30)
returns table (dia date, pessoas bigint, segundos bigint)
language plpgsql stable security definer set search_path = public as $$
declare hoje date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  if not public.admin_seguro() then raise exception 'Acesso restrito ao administrador' using errcode = '42501'; end if;
  return query
    select d.dia, count(distinct d.user_id) filter (where d.segundos >= 60)::bigint, sum(d.segundos)::bigint
      from public.uso_diario d
     where d.dia > hoje - greatest(1, least(coalesce(dias, 30), 365))
     group by d.dia order by d.dia;
end $$;
revoke all on function public.admin_ativos_dia(integer) from public, anon;
grant execute on function public.admin_ativos_dia(integer) to authenticated;
