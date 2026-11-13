-- =====================================================================
-- 072 · Ideali Odonto · Pendência com resposta da clínica + etapas Desenhado e Maquiagem
-- * O laboratório marca a pendência (texto livre). A clínica responde:
--     "Sim, pode prosseguir"  -> o pedido volta para a produção e o prazo recomeça do zero;
--     "Não" + o que vai fazer -> continua pendente (prazo parado) até ela anexar o arquivo;
--     anexou arquivo          -> o pedido volta para a produção e o prazo recomeça do zero.
-- * Etapas que a clínica vê: Desenho -> Desenhado -> Fresagem -> Maquiagem -> Pronto/Enviado.
-- Segurança: só a clínica dona do pedido responde, só enquanto ele está pendente; arquivos na
-- mesma pasta privada do pedido (limite de 20 arquivos, 50 MB cada).
-- * Mini chat em cada pedido, com print colado (Ctrl+V).
-- Rode DEPOIS da 071. Pode rodar de novo.
-- =====================================================================
alter table public.odo_pedidos add column if not exists em_maquiagem boolean not null default false;
alter table public.odo_ped_env add column if not exists resposta text check (char_length(resposta) <= 1000);
alter table public.odo_ped_env add column if not exists resposta_ok boolean;
alter table public.odo_ped_env add column if not exists resposta_em timestamptz;

-- etapa da clínica (agora com Desenhado e Maquiagem); pendência zera a resposta anterior
create or replace function public.odo_ped_env_etapa_sync() returns trigger
language plpgsql security definer set search_path = '' as $$
declare et text;
begin
  if new.envio_id is null then return new; end if;
  if tg_op = 'UPDATE' and new.status is not distinct from old.status
     and new.enviado_inove is not distinct from old.enviado_inove
     and new.falta_info is not distinct from old.falta_info
     and new.desenho_feito is not distinct from old.desenho_feito
     and new.em_maquiagem is not distinct from old.em_maquiagem then return new; end if;
  et := case
          when new.status = 'cancelado' then 'Cancelado'
          when new.status = 'entregue' then 'Entregue'
          when new.status = 'finalizado' then 'Pronto'
          when new.status = 'producao' and new.em_maquiagem then 'Maquiagem'
          when new.status = 'producao' and new.tipo = 'cad' and new.enviado_inove then 'Enviado para fresagem'
          when new.status = 'producao' then 'Em produção'
          when new.status = 'aguardando' then 'Aguardando informação'
          when new.status = 'desenho' and new.desenho_feito then 'Desenhado'
          when new.status = 'desenho' then 'Desenho CAD'
          else null end;
  if et is not null then
    update public.odo_ped_env
       set etapa = et, etapa_em = now(),
           falta_info = case when new.status = 'aguardando' then new.falta_info else null end,
           resposta = case when new.status = 'aguardando' and (tg_op = 'INSERT' or old.status <> 'aguardando' or new.falta_info is distinct from old.falta_info) then null else resposta end,
           resposta_ok = case when new.status = 'aguardando' and (tg_op = 'INSERT' or old.status <> 'aguardando' or new.falta_info is distinct from old.falta_info) then null else resposta_ok end,
           prazo_inicio = case when tg_op = 'UPDATE' and old.status = 'aguardando' and new.status <> 'aguardando' then now() else prazo_inicio end
     where id = new.envio_id and lab_id in (select e.id from public.odo_empresas e where e.user_id = new.user_id);
  end if;
  return new;
end $$;

-- a clínica pode mandar arquivo também enquanto o pedido está pendente
create or replace function public.odo_ped_env_pode_enviar(p_dono text, p_env text) returns boolean
language sql stable security definer set search_path = '' as $$
  select p_dono = (select public.odo_conta())::text
     and exists (select 1 from public.odo_ped_env e where e.id::text = p_env and e.user_id = (select public.odo_conta())
                 and ((e.status = 'enviando' and e.criado_em > now() - interval '2 hours')
                      or (e.status = 'aceito' and e.etapa = 'Aguardando informação')))
     and (select count(*) from storage.objects o where o.bucket_id = 'odonto-ped' and o.name like p_dono || '/' || p_env || '/%') < 20;
$$;

-- a clínica responde a pendência
create or replace function public.odo_ped_env_responde_pend(p_id uuid, p_ok boolean, p_texto text, p_arquivos jsonb default '[]'::jsonb) returns text
language plpgsql security definer set search_path = '' as $$
declare e public.odo_ped_env; a jsonb; arq jsonb; tot bigint; volta boolean; p record;
begin
  select * into e from public.odo_ped_env where id = p_id and user_id = public.odo_conta() for update;
  if e.id is null or e.status <> 'aceito' or e.etapa is distinct from 'Aguardando informação' then raise exception 'sem_pendencia'; end if;
  p_arquivos := coalesce(p_arquivos, '[]'::jsonb);
  if jsonb_typeof(p_arquivos) <> 'array' or jsonb_array_length(p_arquivos) > 20 then raise exception 'arquivos_invalidos'; end if;
  for a in select * from jsonb_array_elements(p_arquivos) loop
    if coalesce(a->>'path','') not like public.odo_conta()::text || '/' || p_id::text || '/%' then raise exception 'arquivo_invalido'; end if;
  end loop;
  arq := coalesce(e.arquivos, '[]'::jsonb) || p_arquivos;
  if jsonb_array_length(arq) > 20 then raise exception 'arquivos_demais'; end if;
  select coalesce(sum((x->>'tam')::bigint), 0) into tot from jsonb_array_elements(arq) x;
  volta := coalesce(p_ok, false) or jsonb_array_length(p_arquivos) > 0;
  update public.odo_ped_env
     set resposta = left(coalesce(nullif(trim(p_texto), ''), case when p_ok then 'Sim, pode prosseguir.' else null end), 1000),
         resposta_ok = p_ok, resposta_em = now(), arquivos = arq, tam_total = tot,
         apagar_em = case when jsonb_array_length(p_arquivos) > 0 then now() + interval '3 days' else apagar_em end,
         arquivos_apagados = case when jsonb_array_length(p_arquivos) > 0 then false else arquivos_apagados end
   where id = p_id;
  if volta then
    -- volta para onde estava: desenho (ou produção, se já tinha ido para a fresagem)
    update public.odo_pedidos o set status = case when o.enviado_inove then 'producao' else 'desenho' end,
           obs = left(coalesce(o.obs, '') || E'\n[Clínica respondeu ' || to_char(now() at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI') || '] ' ||
                      coalesce(nullif(trim(p_texto), ''), case when p_ok then 'Sim, pode prosseguir.' else 'Arquivo anexado.' end), 4000)
     where o.envio_id = p_id and o.status = 'aguardando';
    return 'retomado';
  end if;
  return 'pendente';
end $$;
revoke all on function public.odo_ped_env_responde_pend(uuid, boolean, text, jsonb) from public, anon;
grant execute on function public.odo_ped_env_responde_pend(uuid, boolean, text, jsonb) to authenticated;

-- ===== Mini chat em cada pedido (clínica <-> laboratório), com print colado (Ctrl+V) =====
-- Chave: o pedido digital (envio_id) ou o pedido do laboratório (pedido_id) quando não veio pelo sistema.
-- Só a clínica dona do pedido e o laboratório do pedido leem e escrevem. Imagens em pasta PRIVADA.
create or replace function public.odo_msg_pode(p_envio uuid, p_pedido uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select case
    when p_envio is not null then exists (select 1 from public.odo_ped_env e where e.id = p_envio and e.status <> 'enviando'
                                            and (e.user_id = public.odo_conta() or public.odo_sou_dono_empresa(e.lab_id)))
    when p_pedido is not null then exists (select 1 from public.odo_pedidos o where o.id = p_pedido and (
                                            o.user_id = public.odo_conta()
                                            or exists (select 1 from public.odo_lab_vinculos v join public.odo_empresas l on l.id = v.lab_id
                                                        where v.user_id = public.odo_conta() and v.status = 'aceito' and v.cliente_id = o.cliente_id and l.user_id = o.user_id)))
    else false end;
$$;
revoke all on function public.odo_msg_pode(uuid, uuid) from public, anon;
grant execute on function public.odo_msg_pode(uuid, uuid) to authenticated;

create table if not exists public.odo_ped_msgs (
  id         uuid primary key default gen_random_uuid(),
  envio_id   uuid references public.odo_ped_env(id) on delete cascade,
  pedido_id  uuid references public.odo_pedidos(id) on delete cascade,
  autor      uuid not null default auth.uid() references auth.users(id) on delete cascade,
  autor_nome text check (char_length(autor_nome) <= 80),
  lado       text not null check (lado in ('clinica','lab')),
  texto      text check (char_length(texto) <= 2000),
  anexo      text check (char_length(anexo) <= 300),
  criado_em  timestamptz not null default now(),
  check (envio_id is not null or pedido_id is not null),
  check (coalesce(texto, '') <> '' or anexo is not null)
);
create index if not exists odo_ped_msgs_envio on public.odo_ped_msgs (envio_id, criado_em);
create index if not exists odo_ped_msgs_pedido on public.odo_ped_msgs (pedido_id, criado_em);
alter table public.odo_ped_msgs enable row level security;
revoke all on public.odo_ped_msgs from anon;
grant select, insert on public.odo_ped_msgs to authenticated;
drop policy if exists odo_ped_msgs_ve on public.odo_ped_msgs;
create policy odo_ped_msgs_ve on public.odo_ped_msgs for select to authenticated
  using (public.odo_msg_pode(envio_id, pedido_id));
drop policy if exists odo_ped_msgs_cria on public.odo_ped_msgs;
create policy odo_ped_msgs_cria on public.odo_ped_msgs for insert to authenticated
  with check (autor = (select auth.uid()) and public.odo_msg_pode(envio_id, pedido_id)
              and (anexo is null or anexo like coalesce(envio_id, pedido_id)::text || '/%'));

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('odonto-chat', 'odonto-chat', false, 10485760, array['image/jpeg','image/png','image/webp','application/pdf'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

create or replace function public.odo_msg_pasta_pode(p text) returns boolean
language sql stable security definer set search_path = '' as $$
  select case when p ~ '^[0-9a-f-]{36}$' then
    public.odo_msg_pode((select e.id from public.odo_ped_env e where e.id::text = p), null)
    or public.odo_msg_pode(null, (select o.id from public.odo_pedidos o where o.id::text = p))
  else false end;
$$;
revoke all on function public.odo_msg_pasta_pode(text) from public, anon;
grant execute on function public.odo_msg_pasta_pode(text) to authenticated;

drop policy if exists odonto_chat_envia on storage.objects;
create policy odonto_chat_envia on storage.objects for insert to authenticated
  with check (bucket_id = 'odonto-chat' and public.odo_msg_pasta_pode((storage.foldername(name))[1]));
drop policy if exists odonto_chat_ler on storage.objects;
create policy odonto_chat_ler on storage.objects for select to authenticated
  using (bucket_id = 'odonto-chat' and public.odo_msg_pasta_pode((storage.foldername(name))[1]));

select 'ok: 072 aplicada' as resultado;
