-- =====================================================================
-- 041 · Portal do cliente: a clínica convidada manda trabalhos (com escaneamento) direto para a fila do laboratório.
-- • O laboratório cria um convite por cliente. A clínica abre o link, cria login (Supabase Auth) e fica ligada SÓ a esse cliente.
-- • A clínica nunca lê as tabelas do laboratório: envia e consulta só por funções que conferem o vínculo.
-- • Arquivos no bucket PRIVADO "portal" (pasta <laboratório>/<clínica>/<pedido>/...). Lab baixa e apaga; clínica só envia e vê os dela.
-- =====================================================================

alter table public.pedidos add column if not exists portal_user uuid references auth.users(id) on delete set null;
create index if not exists pedidos_portal on public.pedidos (user_id, portal_user) where portal_user is not null;

-- 1) Convites (um link por cliente do laboratório)
create table if not exists public.portal_convites (
  token      text primary key check (token ~ '^[A-Za-z0-9_-]{24,64}$'),
  lab_id     uuid not null default auth.uid() references auth.users(id) on delete cascade,
  cliente_id uuid not null,
  ativo      boolean not null default true,
  criado_em  timestamptz not null default now(),
  foreign key (cliente_id, lab_id) references public.clientes (id, user_id) on delete cascade
);
alter table public.portal_convites enable row level security;
drop policy if exists portal_convites_lab on public.portal_convites;
create policy portal_convites_lab on public.portal_convites for all to authenticated
  using (lab_id = (select auth.uid())) with check (lab_id = (select auth.uid()));
revoke all on public.portal_convites from anon;

-- 2) Vínculo clínica ↔ laboratório (criado só pela função de aceitar o convite)
create table if not exists public.portal_vinculos (
  cliente_user uuid not null references auth.users(id) on delete cascade,
  lab_id       uuid not null references auth.users(id) on delete cascade,
  cliente_id   uuid not null,
  criado_em    timestamptz not null default now(),
  primary key (cliente_user, lab_id),
  foreign key (cliente_id, lab_id) references public.clientes (id, user_id) on delete cascade
);
alter table public.portal_vinculos enable row level security;
drop policy if exists portal_vinculos_ver on public.portal_vinculos;
create policy portal_vinculos_ver on public.portal_vinculos for select to authenticated
  using (cliente_user = (select auth.uid()) or lab_id = (select auth.uid()));
drop policy if exists portal_vinculos_lab_apaga on public.portal_vinculos;
create policy portal_vinculos_lab_apaga on public.portal_vinculos for delete to authenticated
  using (lab_id = (select auth.uid()));
revoke all on public.portal_vinculos from anon;
revoke insert, update on public.portal_vinculos from authenticated;

-- 3) Arquivos enviados pela clínica
create table if not exists public.portal_arquivos (
  id           uuid primary key default gen_random_uuid(),
  lab_id       uuid not null references auth.users(id) on delete cascade,
  cliente_user uuid not null references auth.users(id) on delete cascade,
  pedido_id    uuid not null,
  path         text not null unique check (char_length(path) <= 300),
  nome         text not null check (char_length(nome) between 1 and 160),
  tamanho      bigint check (tamanho >= 0),
  criado_em    timestamptz not null default now(),
  foreign key (pedido_id, lab_id) references public.pedidos (id, user_id) on delete cascade
);
alter table public.portal_arquivos enable row level security;
drop policy if exists portal_arq_ver on public.portal_arquivos;
create policy portal_arq_ver on public.portal_arquivos for select to authenticated
  using (lab_id = (select auth.uid()) or cliente_user = (select auth.uid()));
drop policy if exists portal_arq_lab_apaga on public.portal_arquivos;
create policy portal_arq_lab_apaga on public.portal_arquivos for delete to authenticated
  using (lab_id = (select auth.uid()));
drop policy if exists portal_arq_cli_grava on public.portal_arquivos;
create policy portal_arq_cli_grava on public.portal_arquivos for insert to authenticated
  with check (cliente_user = (select auth.uid())
    and exists (select 1 from public.pedidos p where p.id = pedido_id and p.user_id = lab_id and p.portal_user = (select auth.uid())));
revoke all on public.portal_arquivos from anon;

-- 3b) A regra "dono = quem está logado" ganha uma exceção controlada: só a função portal_enviar (abaixo)
--     liga esta marca, dentro da própria transação, para gravar o pedido na conta do LABORATÓRIO.
create or replace function public.tg_dono()
returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    if coalesce(current_setting('ideali.portal', true), '') = 'on' then return new; end if;
    new.user_id := coalesce(auth.uid(), new.user_id);
  else
    new.user_id := old.user_id;
  end if;
  return new;
end $$;

-- 4) Aceitar o convite (cria o vínculo da clínica logada)
create or replace function public.portal_aceitar(tk text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare c record; nome_lab text;
begin
  if auth.uid() is null then raise exception 'Entre na sua conta' using errcode = '42501'; end if;
  select * into c from public.portal_convites where token = tk and ativo;
  if c is null then raise exception 'Convite inválido ou cancelado' using errcode = 'P0001'; end if;
  if c.lab_id = auth.uid() then raise exception 'Este convite é do seu próprio laboratório' using errcode = 'P0001'; end if;
  insert into public.portal_vinculos (cliente_user, lab_id, cliente_id) values (auth.uid(), c.lab_id, c.cliente_id)
    on conflict (cliente_user, lab_id) do update set cliente_id = excluded.cliente_id;
  select nome into nome_lab from public.perfis where user_id = c.lab_id;
  return jsonb_build_object('lab_id', c.lab_id, 'lab', coalesce(nome_lab, 'Laboratório'));
end $$;
revoke all on function public.portal_aceitar(text) from public, anon;
grant execute on function public.portal_aceitar(text) to authenticated;

-- 5) O que a clínica vê: seus laboratórios, o nome dela lá e os tipos de trabalho
create or replace function public.portal_info()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'lab_id', v.lab_id,
    'lab', coalesce(pf.nome, 'Laboratório'),
    'cliente', cl.nome,
    'tipos', coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'nome', t.nome, 'forma', t.forma) order by t.nome)
                        from public.tipos_trabalho t where t.user_id = v.lab_id and t.ativo and t.deleted_at is null), '[]'::jsonb)
  ) order by v.criado_em), '[]'::jsonb)
  from public.portal_vinculos v
  join public.clientes cl on cl.id = v.cliente_id
  left join public.perfis pf on pf.user_id = v.lab_id
  where v.cliente_user = auth.uid();
$$;
revoke all on function public.portal_info() from public, anon;
grant execute on function public.portal_info() to authenticated;

-- 6) Enviar trabalho: cria o pedido direto na fila do laboratório (etapa "entrada")
create or replace function public.portal_enviar(lab uuid, p_paciente text, p_tipo uuid, p_elementos smallint[], p_cor text,
  p_obs text, p_prazo date, p_urgente boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v record; t record; pr numeric; qtd int; novo record; n_hoje int;
begin
  select * into v from public.portal_vinculos where cliente_user = auth.uid() and lab_id = lab;
  if v is null then raise exception 'Você não está ligado a este laboratório' using errcode = '42501'; end if;
  select count(*) into n_hoje from public.pedidos where portal_user = auth.uid() and user_id = lab and criado_em > now() - interval '1 day';
  if n_hoje >= 60 then raise exception 'Limite de envios por dia atingido' using errcode = 'P0001'; end if;
  if p_paciente is null or char_length(trim(p_paciente)) < 2 then raise exception 'Digite o nome do paciente' using errcode = 'P0001'; end if;
  select * into t from public.tipos_trabalho where id = p_tipo and user_id = lab and deleted_at is null;
  if p_tipo is not null and t is null then raise exception 'Tipo de trabalho inválido' using errcode = 'P0001'; end if;
  qtd := greatest(coalesce(array_length(p_elementos, 1), 0), 1);
  if t is not null then
    select valor into pr from public.precos_cliente where cliente_id = v.cliente_id and tipo_trabalho_id = t.id and user_id = lab and deleted_at is null limit 1;
    pr := coalesce(pr, t.valor_padrao) * case when t.forma = 'elemento' then qtd else 1 end;
  end if;
  perform set_config('ideali.portal', 'on', true);
  insert into public.pedidos (user_id, numero, cliente_id, paciente, elementos, tipo_trabalho_id, cor, observacoes, valor, urgente, status, prazo, portal_user)
  values (lab, 0, v.cliente_id, left(trim(p_paciente), 80), coalesce(p_elementos, '{}'), t.id, left(nullif(trim(p_cor), ''), 20),
          left(nullif(trim(p_obs), ''), 500), coalesce(pr, 0), coalesce(p_urgente, false), 'entrada', p_prazo, auth.uid())
  returning id, numero into novo;
  perform set_config('ideali.portal', 'off', true);
  return jsonb_build_object('id', novo.id, 'numero', novo.numero);
end $$;
revoke all on function public.portal_enviar(uuid,text,uuid,smallint[],text,text,date,boolean) from public, anon;
grant execute on function public.portal_enviar(uuid,text,uuid,smallint[],text,text,date,boolean) to authenticated;

-- 7) A clínica acompanha os trabalhos que ELA enviou
create or replace function public.portal_meus(lab uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', p.id, 'numero', p.numero, 'paciente', p.paciente, 'tipo', t.nome, 'elementos', p.elementos, 'cor', p.cor,
    'status', p.status, 'recebido', p.recebido_em, 'prazo', p.prazo, 'entregue', p.enviado_em, 'urgente', p.urgente,
    'devolvido', p.cancelado_em is not null, 'motivo', p.cancelado_motivo, 'criado', p.criado_em,
    'arquivos', (select count(*) from public.portal_arquivos a where a.pedido_id = p.id)
  ) order by p.criado_em desc), '[]'::jsonb)
  from public.pedidos p left join public.tipos_trabalho t on t.id = p.tipo_trabalho_id
  where p.user_id = lab and p.portal_user = auth.uid() and p.deleted_at is null
    and exists (select 1 from public.portal_vinculos v where v.cliente_user = auth.uid() and v.lab_id = lab);
$$;
revoke all on function public.portal_meus(uuid) from public, anon;
grant execute on function public.portal_meus(uuid) to authenticated;

-- 8) Bucket privado dos arquivos do portal
insert into storage.buckets (id, name, public) values ('portal', 'portal', false)
on conflict (id) do update set public = false;

drop policy if exists portal_st_cli_envia on storage.objects;
create policy portal_st_cli_envia on storage.objects for insert to authenticated
  with check (bucket_id = 'portal'
    and (storage.foldername(name))[2] = (select auth.uid())::text
    and exists (select 1 from public.portal_vinculos v where v.cliente_user = (select auth.uid()) and v.lab_id::text = (storage.foldername(name))[1]));
drop policy if exists portal_st_ver on storage.objects;
create policy portal_st_ver on storage.objects for select to authenticated
  using (bucket_id = 'portal' and ((storage.foldername(name))[1] = (select auth.uid())::text or (storage.foldername(name))[2] = (select auth.uid())::text));
drop policy if exists portal_st_lab_apaga on storage.objects;
create policy portal_st_lab_apaga on storage.objects for delete to authenticated
  using (bucket_id = 'portal' and (storage.foldername(name))[1] = (select auth.uid())::text);
