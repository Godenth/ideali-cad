-- =====================================================================
-- 057 · Ideali Odonto · Pedido digital: o dentista manda o pedido (com escaneamento e fotos)
-- para o laboratório conectado. Rode DEPOIS da 056.
-- • O pedido chega no laboratório como "Pedido recebido". Quando o lab aceita, ele vira
--   pedido "a fazer" na lista do laboratório (no cliente que o lab escolher).
-- • Arquivos: pasta privada "odonto-ped", só o dentista que enviou e o laboratório que
--   recebeu conseguem abrir (por link assinado). Até 50 MB por arquivo (o sistema compacta
--   antes de enviar), até 20 arquivos e 100 MB por pedido.
-- • Os arquivos são apagados 3 dias depois do envio (o pedido continua, só os arquivos saem).
-- Pode rodar de novo.
-- =====================================================================
create table if not exists public.odo_ped_env (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null default auth.uid() references auth.users(id) on delete cascade, -- dentista
  vinculo_id    uuid not null references public.odo_lab_vinculos(id) on delete cascade,
  lab_id        uuid not null references public.odo_empresas(id) on delete cascade,
  dentista_nome text check (char_length(dentista_nome) <= 80),
  paciente      text check (char_length(paciente) <= 120),
  itens         jsonb not null default '[]'::jsonb check (jsonb_typeof(itens) = 'array' and pg_column_size(itens) < 20000),
  cor           text check (char_length(cor) <= 20),
  prazo         date,
  urgente       boolean not null default false,
  obs           text check (char_length(obs) <= 2000),
  texto_ana     text check (char_length(texto_ana) <= 2000),
  arquivos      jsonb not null default '[]'::jsonb check (jsonb_typeof(arquivos) = 'array' and pg_column_size(arquivos) < 20000),
  tam_total     bigint not null default 0 check (tam_total between 0 and 104857600),
  status        text not null default 'enviando' check (status in ('enviando','enviado','aceito','recusado','cancelado')),
  motivo        text check (char_length(motivo) <= 300),
  apagar_em     timestamptz not null default now() + interval '3 days',
  arquivos_apagados boolean not null default false,
  lab_pedidos   uuid[],
  criado_em     timestamptz not null default now(),
  enviado_em    timestamptz,
  respondido_em timestamptz
);
create index if not exists odo_ped_env_dent on public.odo_ped_env (user_id, criado_em desc);
create index if not exists odo_ped_env_lab on public.odo_ped_env (lab_id, status);
alter table public.odo_ped_env enable row level security;
revoke all on public.odo_ped_env from anon;

create or replace function public.odo_sou_dono_empresa(p_emp uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.odo_empresas e where e.id = p_emp and e.user_id = (select auth.uid()));
$$;
revoke all on function public.odo_sou_dono_empresa(uuid) from public, anon;
grant execute on function public.odo_sou_dono_empresa(uuid) to authenticated;

drop policy if exists odo_ped_env_ve on public.odo_ped_env;
create policy odo_ped_env_ve on public.odo_ped_env for select to authenticated
  using (user_id = (select auth.uid()) or (status <> 'enviando' and public.odo_sou_dono_empresa(lab_id)));
-- o dentista cria o rascunho, só para laboratório conectado (aceito)
drop policy if exists odo_ped_env_cria on public.odo_ped_env;
create policy odo_ped_env_cria on public.odo_ped_env for insert to authenticated
  with check (user_id = (select auth.uid()) and status = 'enviando' and arquivos = '[]'::jsonb
    and exists (select 1 from public.odo_lab_vinculos v where v.id = vinculo_id and v.user_id = (select auth.uid())
                and v.lab_id = odo_ped_env.lab_id and v.status = 'aceito'));
-- o resto só pelas funções abaixo

-- o laboratório guarda qual cliente do cadastro dele é esse dentista
alter table public.odo_lab_vinculos add column if not exists cliente_id uuid references public.odo_clientes(id) on delete set null;
alter table public.odo_pedidos add column if not exists envio_id uuid references public.odo_ped_env(id) on delete set null;

-- ===== arquivos =====
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('odonto-ped', 'odonto-ped', false, 52428800,
        array['application/zip','image/jpeg','image/png','image/webp','application/pdf'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

-- caminho: <dentista>/<envio>/<arquivo>
create or replace function public.odo_ped_env_pode_enviar(p_dono text, p_env text) returns boolean
language sql stable security definer set search_path = '' as $$
  select p_dono = (select auth.uid())::text
     and exists (select 1 from public.odo_ped_env e where e.id::text = p_env and e.user_id = (select auth.uid())
                 and e.status = 'enviando' and e.criado_em > now() - interval '2 hours')
     and (select count(*) from storage.objects o where o.bucket_id = 'odonto-ped' and o.name like p_dono || '/' || p_env || '/%') < 20;
$$;
create or replace function public.odo_ped_env_pode_ver(p_env text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.odo_ped_env e where e.id::text = p_env
                 and (e.user_id = (select auth.uid())
                      or (e.status <> 'enviando' and exists (select 1 from public.odo_empresas x where x.id = e.lab_id and x.user_id = (select auth.uid())))));
$$;
revoke all on function public.odo_ped_env_pode_enviar(text, text) from public, anon;
revoke all on function public.odo_ped_env_pode_ver(text) from public, anon;
grant execute on function public.odo_ped_env_pode_enviar(text, text) to authenticated;
grant execute on function public.odo_ped_env_pode_ver(text) to authenticated;

drop policy if exists odonto_ped_envia on storage.objects;
create policy odonto_ped_envia on storage.objects for insert to authenticated
  with check (bucket_id = 'odonto-ped'
    and public.odo_ped_env_pode_enviar((storage.foldername(name))[1], (storage.foldername(name))[2]));
drop policy if exists odonto_ped_ler on storage.objects;
create policy odonto_ped_ler on storage.objects for select to authenticated
  using (bucket_id = 'odonto-ped' and public.odo_ped_env_pode_ver((storage.foldername(name))[2]));
drop policy if exists odonto_ped_apaga on storage.objects;
create policy odonto_ped_apaga on storage.objects for delete to authenticated
  using (bucket_id = 'odonto-ped' and public.odo_ped_env_pode_ver((storage.foldername(name))[2]));

-- ===== funções =====
-- dentista: fecha o envio depois de mandar os arquivos
create or replace function public.odo_ped_env_fecha(p_id uuid, p_dados jsonb) returns boolean
language plpgsql security definer set search_path = '' as $$
declare e public.odo_ped_env; arq jsonb := coalesce(p_dados->'arquivos','[]'::jsonb); a jsonb; tot bigint := 0; nm text;
begin
  select * into e from public.odo_ped_env where id = p_id and user_id = auth.uid();
  if e.id is null or e.status <> 'enviando' then raise exception 'Pedido não encontrado'; end if;
  if jsonb_typeof(arq) <> 'array' or jsonb_array_length(arq) > 20 then raise exception 'Arquivos inválidos'; end if;
  for a in select * from jsonb_array_elements(arq) loop
    if coalesce(a->>'path','') not like auth.uid()::text || '/' || p_id::text || '/%' then raise exception 'Arquivo inválido'; end if;
    tot := tot + coalesce((a->>'tam')::bigint, 0);
  end loop;
  if tot > 104857600 then raise exception 'Passou de 100 MB'; end if;
  select coalesce((select x.nome from public.odo_empresas x where x.user_id = auth.uid()),
                  (select p.nome from public.odo_perfis p where p.user_id = auth.uid())) into nm;
  update public.odo_ped_env set arquivos = arq, tam_total = tot, status = 'enviado', enviado_em = now(),
         apagar_em = now() + interval '3 days', dentista_nome = left(nm, 80),
         paciente = left(p_dados->>'paciente', 120), itens = coalesce(p_dados->'itens','[]'::jsonb),
         cor = left(p_dados->>'cor', 20), prazo = nullif(p_dados->>'prazo','')::date,
         urgente = coalesce((p_dados->>'urgente')::boolean, false), obs = left(p_dados->>'obs', 2000),
         texto_ana = left(p_dados->>'texto_ana', 2000)
   where id = p_id;
  return true;
end $$;

-- dentista: cancela enquanto o lab não aceitou
create or replace function public.odo_ped_env_cancela(p_id uuid) returns boolean
language plpgsql security definer set search_path = '' as $$
begin
  update public.odo_ped_env set status = 'cancelado', respondido_em = now(), apagar_em = now()
   where id = p_id and user_id = auth.uid() and status in ('enviando','enviado');
  return found;
end $$;

-- laboratório: aceita (vira pedido a fazer no cliente escolhido) ou recusa
create or replace function public.odo_ped_env_responde(p_id uuid, p_ok boolean, p_cliente uuid default null, p_motivo text default null) returns int
language plpgsql security definer set search_path = '' as $$
declare e public.odo_ped_env; lab public.odo_empresas; c public.odo_clientes; it jsonb; ids uuid[] := '{}'; nid uuid; n int := 0; tot int; num int; ds smallint[];
begin
  select * into e from public.odo_ped_env where id = p_id;
  if e.id is null or e.status <> 'enviado' then raise exception 'Pedido não encontrado'; end if;
  select * into lab from public.odo_empresas where id = e.lab_id and user_id = auth.uid();
  if lab.id is null then raise exception 'Sem permissão'; end if;
  if not p_ok then
    update public.odo_ped_env set status = 'recusado', motivo = left(p_motivo, 300), respondido_em = now() where id = p_id;
    return 0;
  end if;
  if p_cliente is not null then
    select * into c from public.odo_clientes where id = p_cliente and user_id = auth.uid();
    if c.id is null then raise exception 'Cliente inválido'; end if;
    update public.odo_lab_vinculos set cliente_id = c.id where id = e.vinculo_id;
  else
    select cl.* into c from public.odo_lab_vinculos v join public.odo_clientes cl on cl.id = v.cliente_id and cl.user_id = auth.uid()
     where v.id = e.vinculo_id;
  end if;
  tot := greatest(jsonb_array_length(e.itens), 1);
  select coalesce(max(numero), 0) into num from public.odo_pedidos where user_id = auth.uid();
  for it in select * from jsonb_array_elements(case when jsonb_array_length(e.itens) = 0 then '[{}]'::jsonb else e.itens end) loop
    n := n + 1; num := num + 1;
    select coalesce(array_agg(x::smallint), null) into ds from jsonb_array_elements_text(coalesce(it->'dentes','[]'::jsonb)) x where x ~ '^\d{2}$';
    insert into public.odo_pedidos (user_id, numero, cliente_id, cliente_reg, cliente_nome, paciente, tipo, trabalho, descricao, dentes, qtd, cor, material,
                                    sobre_implante, prazo, urgente, status, origem, obs, envio_id)
    values (auth.uid(), num, c.id, c.reg, left(coalesce(c.nome, e.dentista_nome), 120), e.paciente,
            case when it->>'tipo' = 'analogico' then 'analogico' else 'cad' end,
            left(coalesce(nullif(it->>'trabalho',''), 'Pedido digital'), 120),
            left('Pedido digital enviado pelo Ideali' || case when tot > 1 then ' (' || n || ' de ' || tot || ')' else '' end ||
                 coalesce(E'\n' || nullif(e.texto_ana,''), '') || coalesce(E'\nObs.: ' || nullif(e.obs,''), ''), 4000),
            case when cardinality(ds) > 0 then ds[1:32] else null end,
            least(greatest(coalesce(nullif(it->>'qtd','')::int, cardinality(ds), 1), 0), 99),
            e.cor, left(it->>'material', 60), coalesce((it->>'sobre_implante')::boolean, false), e.prazo, e.urgente,
            case when it->>'tipo' = 'analogico' then 'producao' else 'desenho' end, 'portal', null, e.id)
    returning id into nid;
    ids := ids || nid;
  end loop;
  update public.odo_ped_env set status = 'aceito', respondido_em = now(), lab_pedidos = ids where id = p_id;
  return n;
end $$;

-- marca que os arquivos já foram apagados (quem apaga é o próprio app, depois dos 3 dias)
create or replace function public.odo_ped_env_limpo(p_id uuid) returns boolean
language plpgsql security definer set search_path = '' as $$
begin
  update public.odo_ped_env e set arquivos_apagados = true
   where e.id = p_id and e.apagar_em < now()
     and (e.user_id = auth.uid() or public.odo_sou_dono_empresa(e.lab_id));
  return found;
end $$;

revoke all on function public.odo_ped_env_fecha(uuid, jsonb) from public, anon;
revoke all on function public.odo_ped_env_cancela(uuid) from public, anon;
revoke all on function public.odo_ped_env_responde(uuid, boolean, uuid, text) from public, anon;
revoke all on function public.odo_ped_env_limpo(uuid) from public, anon;
grant execute on function public.odo_ped_env_fecha(uuid, jsonb) to authenticated;
grant execute on function public.odo_ped_env_cancela(uuid) to authenticated;
grant execute on function public.odo_ped_env_responde(uuid, boolean, uuid, text) to authenticated;
grant execute on function public.odo_ped_env_limpo(uuid) to authenticated;
grant select, insert on public.odo_ped_env to authenticated;

select 'ok: 057 aplicada' as resultado;
