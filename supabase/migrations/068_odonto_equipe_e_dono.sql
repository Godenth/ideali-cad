-- =====================================================================
-- 068 · Ideali Odonto · Equipe da empresa e passagem para o dono
-- Pedido do dono em 13/11/2026: quem cadastra a clínica muitas vezes é a funcionária (ASB,
-- secretária). Ela diz a posição dela; quando o dono entrar, ela passa a empresa para ele
-- por um link. Funcionários entram com login próprio e mexem em TUDO, MENOS no financeiro.
--
-- Segurança:
--   * odo_conta() = a conta da empresa em que a pessoa trabalha (dono), ou ela mesma.
--     As tabelas da empresa (empresa, clientes, pedidos, preços, cadistas, pré-cadastros,
--     laboratórios conectados, pedidos digitais) passam a valer para a conta da empresa.
--   * Financeiro (odo_fin_*, comprovantes, conta espelho) continua SÓ do dono.
--   * Funcionário não apaga a empresa, não convida ninguém e não passa a empresa adiante.
--   * Convite por link de uso único, vale 7 dias. Só o dono cria e corta acessos.
-- Rode DEPOIS da 067. Pode rodar de novo.
-- =====================================================================

-- 1) Equipe e convites
create table if not exists public.odo_membros (
  id         uuid primary key default gen_random_uuid(),
  dono_id    uuid not null references auth.users(id) on delete cascade,
  user_id    uuid not null unique references auth.users(id) on delete cascade,
  nome       text check (char_length(nome) <= 80),
  cargo      text check (char_length(cargo) <= 60),
  ativo      boolean not null default true,
  criado_em  timestamptz not null default now(),
  check (dono_id <> user_id)
);
alter table public.odo_membros enable row level security;
revoke all on public.odo_membros from anon;
grant select, update, delete on public.odo_membros to authenticated;
drop policy if exists odo_membros_ve on public.odo_membros;
create policy odo_membros_ve on public.odo_membros for select to authenticated
  using (dono_id = (select auth.uid()) or user_id = (select auth.uid()));
drop policy if exists odo_membros_muda on public.odo_membros;
create policy odo_membros_muda on public.odo_membros for update to authenticated
  using (dono_id = (select auth.uid())) with check (dono_id = (select auth.uid()));
drop policy if exists odo_membros_apaga on public.odo_membros;
create policy odo_membros_apaga on public.odo_membros for delete to authenticated
  using (dono_id = (select auth.uid()));

create table if not exists public.odo_convites_emp (
  id         uuid primary key default gen_random_uuid(),
  dono_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  tipo       text not null check (tipo in ('funcionario','dono')),
  nome       text check (char_length(nome) <= 80),
  cargo      text check (char_length(cargo) <= 60),
  token      text not null unique default replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''),
  expira_em  timestamptz not null default now() + interval '7 days',
  ativo      boolean not null default true,
  aceito_por uuid references auth.users(id) on delete set null,
  aceito_em  timestamptz,
  criado_em  timestamptz not null default now()
);
alter table public.odo_convites_emp enable row level security;
revoke all on public.odo_convites_emp from anon;
grant select, insert, update, delete on public.odo_convites_emp to authenticated;
drop policy if exists odo_convites_emp_dono on public.odo_convites_emp;
create policy odo_convites_emp_dono on public.odo_convites_emp for all to authenticated
  using (dono_id = (select auth.uid()))
  with check (dono_id = (select auth.uid()) and not exists (select 1 from public.odo_membros m where m.user_id = (select auth.uid()) and m.ativo));

-- contas antigas do dono (para os arquivos guardados antes da passagem continuarem abrindo)
create table if not exists public.odo_contas_antigas (
  antigo_id uuid primary key,
  dono_id   uuid not null references auth.users(id) on delete cascade,
  criado_em timestamptz not null default now()
);
alter table public.odo_contas_antigas enable row level security;
revoke all on public.odo_contas_antigas from anon, authenticated;

-- 2) A conta da empresa de quem está logado
create or replace function public.odo_conta() returns uuid
language sql stable security definer set search_path = '' as $$
  select coalesce((select m.dono_id from public.odo_membros m where m.user_id = auth.uid() and m.ativo limit 1), auth.uid());
$$;
revoke all on function public.odo_conta() from public, anon;
grant execute on function public.odo_conta() to authenticated;

create or replace function public.odo_pasta_minha(p text) returns boolean
language sql stable security definer set search_path = '' as $$
  select p = auth.uid()::text or exists (select 1 from public.odo_contas_antigas a where a.antigo_id::text = p and a.dono_id = auth.uid());
$$;
revoke all on function public.odo_pasta_minha(text) from public, anon;
grant execute on function public.odo_pasta_minha(text) to authenticated;

-- 2b) o funcionário enxerga o cadastro do dono (para abrir o painel da empresa)
drop policy if exists odo_perfis_equipe on public.odo_perfis;
create policy odo_perfis_equipe on public.odo_perfis for select to authenticated
  using (user_id = (select public.odo_conta()));

-- 3) Tabelas da empresa: valem para a conta da empresa (dono + funcionários)
alter table public.odo_empresas      alter column user_id set default public.odo_conta();
alter table public.odo_clientes      alter column user_id set default public.odo_conta();
alter table public.odo_pedidos       alter column user_id set default public.odo_conta();
alter table public.odo_precos        alter column user_id set default public.odo_conta();
alter table public.odo_cadistas      alter column user_id set default public.odo_conta();
alter table public.odo_pre_cadastros alter column user_id set default public.odo_conta();
alter table public.odo_ped_env       alter column user_id set default public.odo_conta();
alter table public.odo_lab_vinculos  alter column user_id set default public.odo_conta();

drop policy if exists odo_empresas_dono on public.odo_empresas;
drop policy if exists odo_empresas_ve on public.odo_empresas;
create policy odo_empresas_ve on public.odo_empresas for select to authenticated using (user_id = (select public.odo_conta()));
drop policy if exists odo_empresas_muda on public.odo_empresas;
create policy odo_empresas_muda on public.odo_empresas for update to authenticated
  using (user_id = (select public.odo_conta())) with check (user_id = (select public.odo_conta()));
drop policy if exists odo_empresas_cria on public.odo_empresas;
create policy odo_empresas_cria on public.odo_empresas for insert to authenticated with check (user_id = (select auth.uid()));
drop policy if exists odo_empresas_apaga on public.odo_empresas;
create policy odo_empresas_apaga on public.odo_empresas for delete to authenticated using (user_id = (select auth.uid()));

drop policy if exists odo_clientes_dono on public.odo_clientes;
create policy odo_clientes_dono on public.odo_clientes for all to authenticated
  using (user_id = (select public.odo_conta())) with check (user_id = (select public.odo_conta()));
drop policy if exists odo_pedidos_dono on public.odo_pedidos;
create policy odo_pedidos_dono on public.odo_pedidos for all to authenticated
  using (user_id = (select public.odo_conta())) with check (user_id = (select public.odo_conta()));
drop policy if exists odo_precos_dono on public.odo_precos;
create policy odo_precos_dono on public.odo_precos for all to authenticated
  using (user_id = (select public.odo_conta())) with check (user_id = (select public.odo_conta()));
drop policy if exists odo_cadistas_dono on public.odo_cadistas;
create policy odo_cadistas_dono on public.odo_cadistas for all to authenticated
  using (user_id = (select public.odo_conta())) with check (user_id = (select public.odo_conta()));
drop policy if exists odo_pre_dono on public.odo_pre_cadastros;
create policy odo_pre_dono on public.odo_pre_cadastros for all to authenticated
  using (user_id = (select public.odo_conta())) with check (user_id = (select public.odo_conta()));

drop policy if exists odo_lab_vinculos_ve on public.odo_lab_vinculos;
create policy odo_lab_vinculos_ve on public.odo_lab_vinculos for select to authenticated
  using (user_id = (select public.odo_conta())
         or exists (select 1 from public.odo_empresas e where e.id = odo_lab_vinculos.lab_id and e.user_id = (select public.odo_conta())));
drop policy if exists odo_lab_vinculos_apaga on public.odo_lab_vinculos;
create policy odo_lab_vinculos_apaga on public.odo_lab_vinculos for delete to authenticated
  using (user_id = (select public.odo_conta()));

drop policy if exists odo_ped_env_cria on public.odo_ped_env;
create policy odo_ped_env_cria on public.odo_ped_env for insert to authenticated
  with check (user_id = (select public.odo_conta()) and status = 'enviando' and arquivos = '[]'::jsonb
              and exists (select 1 from public.odo_lab_vinculos v where v.id = odo_ped_env.vinculo_id and v.user_id = (select public.odo_conta())
                          and v.lab_id = odo_ped_env.lab_id and v.status = 'aceito'));
drop policy if exists odo_ped_env_ve on public.odo_ped_env;
create policy odo_ped_env_ve on public.odo_ped_env for select to authenticated
  using (user_id = (select public.odo_conta()) or (status <> 'enviando' and public.odo_sou_dono_empresa(lab_id)));

-- comprovantes e extratos do financeiro: só o dono, inclusive os guardados na conta antiga
drop policy if exists odonto_fin_ler on storage.objects;
create policy odonto_fin_ler on storage.objects for select to authenticated
  using (bucket_id = 'odonto-fin' and public.odo_pasta_minha((storage.foldername(name))[1]));
drop policy if exists odonto_fin_apagar on storage.objects;
create policy odonto_fin_apagar on storage.objects for delete to authenticated
  using (bucket_id = 'odonto-fin' and public.odo_pasta_minha((storage.foldername(name))[1]));
drop policy if exists odonto_fin_trocar on storage.objects;
create policy odonto_fin_trocar on storage.objects for update to authenticated
  using (bucket_id = 'odonto-fin' and public.odo_pasta_minha((storage.foldername(name))[1]))
  with check (bucket_id = 'odonto-fin' and public.odo_pasta_minha((storage.foldername(name))[1]));

-- 4) Funções da empresa passam a usar a conta da empresa (mesmo código, só troca auth.uid() por odo_conta())
CREATE OR REPLACE FUNCTION public.odo_clinica_pedidos_lab()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(jsonb_agg(x order by x->>'criado_em' desc), '[]'::jsonb) from (
    select jsonb_build_object(
      'id', p.id, 'lab_id', e.id, 'lab_nome', e.nome, 'numero', p.numero, 'paciente', p.paciente,
      'trabalho', p.trabalho, 'dentes', to_jsonb(coalesce(p.dentes, '{}'::smallint[])), 'material', p.material, 'cor', p.cor,
      'sobre_implante', p.sobre_implante, 'prazo', p.prazo, 'urgente', p.urgente, 'criado_em', p.criado_em,
      'etapa', case
          when p.status = 'cancelado' then 'Cancelado'
          when p.status = 'entregue' then 'Entregue'
          when p.status = 'finalizado' then 'Pronto'
          when p.status = 'producao' and p.tipo = 'cad' and p.enviado_inove then 'Enviado para fresagem'
          when p.status = 'producao' then 'Em produção'
          when p.status = 'aguardando' then 'Aguardando informação'
          else 'Desenho CAD' end) as x
    from public.odo_lab_vinculos v
    join public.odo_empresas e on e.id = v.lab_id
    join public.odo_pedidos p on p.user_id = e.user_id and p.cliente_id = v.cliente_id
    where v.user_id = public.odo_conta() and v.status = 'aceito' and v.cliente_id is not null
      and p.envio_id is null and p.status <> 'orcamento'
    order by p.criado_em desc
    limit 300) q;
$function$
;

CREATE OR REPLACE FUNCTION public.odo_lab_busca(p_codigo integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select case when public.odo_conta() is null then null else
    (select jsonb_build_object('codigo', e.codigo, 'nome', e.nome, 'cidade', e.cidade, 'uf', e.uf)
       from public.odo_empresas e where e.codigo = p_codigo and e.tipo = 'lab') end;
$function$
;

CREATE OR REPLACE FUNCTION public.odo_lab_convida(p_codigo integer)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare eu uuid := public.odo_conta(); l public.odo_empresas; nm text; nid uuid; n int;
begin
  if eu is null then raise exception 'Entre na sua conta'; end if;
  select * into l from public.odo_empresas where codigo = p_codigo and tipo = 'lab';
  if l.id is null then raise exception 'Laboratório não encontrado'; end if;
  if l.user_id = eu then raise exception 'Esse é o seu próprio laboratório'; end if;
  select count(*) into n from public.odo_lab_vinculos where user_id = eu and criado_em > now() - interval '1 day';
  if n >= 30 then raise exception 'Muitos convites hoje. Tente amanhã.'; end if;
  select coalesce((select e.nome from public.odo_empresas e where e.user_id = eu),
                  (select p.nome from public.odo_perfis p where p.user_id = eu)) into nm;
  insert into public.odo_lab_vinculos (user_id, lab_id, lab_nome, lab_local, quem_nome)
  values (eu, l.id, l.nome, left(concat_ws(' / ', l.cidade, l.uf), 80), left(nm, 80))
  on conflict (user_id, lab_id) do update set status = case when public.odo_lab_vinculos.status = 'recusado' then 'pendente' else public.odo_lab_vinculos.status end,
                                              respondido_em = case when public.odo_lab_vinculos.status = 'recusado' then null else public.odo_lab_vinculos.respondido_em end
  returning id into nid;
  return nid;
end $function$
;

CREATE OR REPLACE FUNCTION public.odo_lab_responde(p_id uuid, p_ok boolean)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  update public.odo_lab_vinculos v set status = case when p_ok then 'aceito' else 'recusado' end, respondido_em = now()
   where v.id = p_id and exists (select 1 from public.odo_empresas e where e.id = v.lab_id and e.user_id = public.odo_conta());
  return found;
end $function$
;

CREATE OR REPLACE FUNCTION public.odo_lab_vincula_cliente(p_vinculo uuid, p_cliente uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not exists (select 1 from public.odo_lab_vinculos v join public.odo_empresas e on e.id = v.lab_id
                  where v.id = p_vinculo and e.user_id = public.odo_conta()) then
    raise exception 'vinculo_nao_e_seu';
  end if;
  if p_cliente is not null and not exists (select 1 from public.odo_clientes c where c.id = p_cliente and c.user_id = public.odo_conta()) then
    raise exception 'cliente_nao_e_seu';
  end if;
  update public.odo_lab_vinculos set cliente_id = p_cliente where id = p_vinculo;
end $function$
;

CREATE OR REPLACE FUNCTION public.odo_labs_parceiros()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
      'vinculo', v.id, 'lab_id', e.id, 'status', v.status, 'codigo', e.codigo, 'nome', e.nome, 'cidade', e.cidade, 'uf', e.uf, 'rt', e.rt,
      'contato', case when v.status = 'aceito' then coalesce(e.dados->'contato', '{}'::jsonb) else '{}'::jsonb end)), '[]'::jsonb)
  from public.odo_lab_vinculos v join public.odo_empresas e on e.id = v.lab_id
  where v.user_id = public.odo_conta() and v.status in ('pendente','aceito');
$function$
;

CREATE OR REPLACE FUNCTION public.odo_ped_env_cancela(p_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  update public.odo_ped_env set status = 'cancelado', respondido_em = now(), apagar_em = now()
   where id = p_id and user_id = public.odo_conta() and status in ('enviando','enviado');
  return found;
end $function$
;

CREATE OR REPLACE FUNCTION public.odo_ped_env_fecha(p_id uuid, p_dados jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare e public.odo_ped_env; arq jsonb := coalesce(p_dados->'arquivos','[]'::jsonb); a jsonb; tot bigint := 0; nm text;
begin
  select * into e from public.odo_ped_env where id = p_id and user_id = public.odo_conta();
  if e.id is null or e.status <> 'enviando' then raise exception 'Pedido não encontrado'; end if;
  if jsonb_typeof(arq) <> 'array' or jsonb_array_length(arq) > 20 then raise exception 'Arquivos inválidos'; end if;
  for a in select * from jsonb_array_elements(arq) loop
    if coalesce(a->>'path','') not like public.odo_conta()::text || '/' || p_id::text || '/%' then raise exception 'Arquivo inválido'; end if;
    tot := tot + coalesce((a->>'tam')::bigint, 0);
  end loop;
  if tot > 104857600 then raise exception 'Passou de 100 MB'; end if;
  select coalesce((select x.nome from public.odo_empresas x where x.user_id = public.odo_conta()),
                  (select p.nome from public.odo_perfis p where p.user_id = public.odo_conta())) into nm;
  update public.odo_ped_env set arquivos = arq, tam_total = tot, status = 'enviado', enviado_em = now(),
         apagar_em = now() + interval '3 days', dentista_nome = left(nm, 80),
         paciente = left(p_dados->>'paciente', 120), itens = coalesce(p_dados->'itens','[]'::jsonb),
         cor = left(p_dados->>'cor', 20), prazo = nullif(p_dados->>'prazo','')::date,
         urgente = coalesce((p_dados->>'urgente')::boolean, false), obs = left(p_dados->>'obs', 2000),
         texto_ana = left(p_dados->>'texto_ana', 2000)
   where id = p_id;
  return true;
end $function$
;

CREATE OR REPLACE FUNCTION public.odo_ped_env_limpo(p_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  update public.odo_ped_env e set arquivos_apagados = true
   where e.id = p_id and e.apagar_em < now()
     and (e.user_id = public.odo_conta() or public.odo_sou_dono_empresa(e.lab_id));
  return found;
end $function$
;

CREATE OR REPLACE FUNCTION public.odo_ped_env_pode_enviar(p_dono text, p_env text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select p_dono = (select public.odo_conta())::text
     and exists (select 1 from public.odo_ped_env e where e.id::text = p_env and e.user_id = (select public.odo_conta())
                 and e.status = 'enviando' and e.criado_em > now() - interval '2 hours')
     and (select count(*) from storage.objects o where o.bucket_id = 'odonto-ped' and o.name like p_dono || '/' || p_env || '/%') < 20;
$function$
;

CREATE OR REPLACE FUNCTION public.odo_ped_env_pode_ver(p_env text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists (select 1 from public.odo_ped_env e where e.id::text = p_env
                 and (e.user_id = (select public.odo_conta())
                      or (e.status <> 'enviando' and exists (select 1 from public.odo_empresas x where x.id = e.lab_id and x.user_id = (select public.odo_conta())))));
$function$
;

CREATE OR REPLACE FUNCTION public.odo_ped_env_responde(p_id uuid, p_ok boolean, p_cliente uuid DEFAULT NULL::uuid, p_motivo text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare e public.odo_ped_env; lab public.odo_empresas; c public.odo_clientes; it jsonb; ids uuid[] := '{}'; nid uuid; n int := 0; tot int; num int; ds smallint[];
begin
  select * into e from public.odo_ped_env where id = p_id;
  if e.id is null or e.status <> 'enviado' then raise exception 'Pedido não encontrado'; end if;
  select * into lab from public.odo_empresas where id = e.lab_id and user_id = public.odo_conta();
  if lab.id is null then raise exception 'Sem permissão'; end if;
  if not p_ok then
    update public.odo_ped_env set status = 'recusado', motivo = left(p_motivo, 300), respondido_em = now() where id = p_id;
    return 0;
  end if;
  if p_cliente is not null then
    select * into c from public.odo_clientes where id = p_cliente and user_id = public.odo_conta();
    if c.id is null then raise exception 'Cliente inválido'; end if;
    update public.odo_lab_vinculos set cliente_id = c.id where id = e.vinculo_id;
  else
    select cl.* into c from public.odo_lab_vinculos v join public.odo_clientes cl on cl.id = v.cliente_id and cl.user_id = public.odo_conta()
     where v.id = e.vinculo_id;
  end if;
  tot := greatest(jsonb_array_length(e.itens), 1);
  select coalesce(max(numero), 0) into num from public.odo_pedidos where user_id = public.odo_conta();
  for it in select * from jsonb_array_elements(case when jsonb_array_length(e.itens) = 0 then '[{}]'::jsonb else e.itens end) loop
    n := n + 1; num := num + 1;
    select coalesce(array_agg(x::smallint), null) into ds from jsonb_array_elements_text(coalesce(it->'dentes','[]'::jsonb)) x where x ~ '^\d{2}$';
    insert into public.odo_pedidos (user_id, numero, cliente_id, cliente_reg, cliente_nome, paciente, tipo, trabalho, descricao, dentes, qtd, cor, material,
                                    sobre_implante, prazo, urgente, status, origem, obs, envio_id)
    values (public.odo_conta(), num, c.id, c.reg, left(coalesce(c.nome, e.dentista_nome), 120), e.paciente,
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
end $function$
;

CREATE OR REPLACE FUNCTION public.odo_sou_dono_empresa(p_emp uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists (select 1 from public.odo_empresas e where e.id = p_emp and e.user_id = (select public.odo_conta()));
$function$
;


-- travas: o dono da linha não muda, EXCETO durante a passagem da empresa (função abaixo)
CREATE OR REPLACE FUNCTION public.odo_dono_fixo()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin if tg_op = 'UPDATE' and coalesce(current_setting('odo.transferindo', true), '') <> '1' then new.user_id := old.user_id; end if;
  if tg_table_name <> 'odo_precos' then new.atualizado_em := now(); end if; return new; end $function$
;

CREATE OR REPLACE FUNCTION public.odo_parceiros_trava()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  if tg_op = 'INSERT' then
    new.parceiro_id := null; new.aceito_em := null;
    new.token := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
    new.expira_em := now() + interval '7 days';
  else
    if coalesce(current_setting('odo.transferindo', true), '') <> '1' then new.dono_id := old.dono_id; end if; new.token := old.token; new.criado_em := old.criado_em;
    if coalesce(current_setting('odo.aceitando', true), '') <> '1' then
      new.parceiro_id := old.parceiro_id; new.aceito_em := old.aceito_em; new.expira_em := old.expira_em;
    end if;
  end if;
  return new; end $function$
;

CREATE OR REPLACE FUNCTION public.odo_fin_leit_trava()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  if not exists (select 1 from public.odo_fin_pagamentos p where p.id = new.pagamento_id and p.user_id = new.dono_id) then
    raise exception 'pagamento inválido'; end if;
  if tg_op = 'UPDATE' then
    if coalesce(current_setting('odo.transferindo', true), '') <> '1' then new.dono_id := old.dono_id; end if; new.pagamento_id := old.pagamento_id; new.parceiro_id := old.parceiro_id; new.criado_em := old.criado_em;
    new.aberto_em := coalesce(old.aberto_em, case when new.aberto_em is not null then now() end);
    new.confirmado_em := coalesce(old.confirmado_em, case when new.confirmado_em is not null then now() end);
  else
    new.aberto_em := case when new.aberto_em is not null then now() end;
    new.confirmado_em := case when new.confirmado_em is not null then now() end;
  end if;
  if new.confirmado_em is not null and new.aberto_em is null then raise exception 'abra o comprovante antes de confirmar'; end if;
  return new; end $function$
;

-- 5) Aceitar convite: funcionário entra na equipe; dono recebe a empresa inteira
create or replace function public.odo_convite_aceita(p_token text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare c public.odo_convites_emp; eu uuid := auth.uid(); antigo uuid; nm text;
begin
  if eu is null then raise exception 'entre_primeiro'; end if;
  select * into c from public.odo_convites_emp where token = p_token for update;
  if c.id is null or not c.ativo or c.aceito_em is not null then raise exception 'convite_invalido'; end if;
  if c.expira_em < now() then raise exception 'convite_vencido'; end if;
  if c.dono_id = eu then raise exception 'convite_e_seu'; end if;
  if exists (select 1 from public.odo_empresas e where e.user_id = eu) then raise exception 'ja_tem_empresa'; end if;
  select nome into nm from public.odo_perfis where user_id = eu;

  if c.tipo = 'funcionario' then
    insert into public.odo_membros (dono_id, user_id, nome, cargo, ativo)
    values (c.dono_id, eu, coalesce(nm, c.nome), c.cargo, true)
    on conflict (user_id) do update set dono_id = excluded.dono_id, nome = excluded.nome, cargo = excluded.cargo, ativo = true;
  else
    antigo := c.dono_id;
    if exists (select 1 from public.odo_membros m where m.user_id = antigo and m.ativo) then raise exception 'convite_invalido'; end if;
    if exists (select 1 from public.odo_clientes where user_id = eu) or exists (select 1 from public.odo_pedidos where user_id = eu)
       or exists (select 1 from public.odo_fin_meses where user_id = eu) then raise exception 'ja_tem_dados'; end if;
    delete from public.odo_membros where user_id = eu;
    perform set_config('odo.transferindo', '1', true);
    update public.odo_empresas      set user_id = eu where user_id = antigo;
    update public.odo_clientes      set user_id = eu where user_id = antigo;
    update public.odo_pedidos       set user_id = eu where user_id = antigo;
    update public.odo_precos        set user_id = eu where user_id = antigo;
    update public.odo_cadistas      set user_id = eu where user_id = antigo;
    update public.odo_pre_cadastros set user_id = eu where user_id = antigo;
    update public.odo_ped_env       set user_id = eu where user_id = antigo;
    update public.odo_lab_vinculos  set user_id = eu where user_id = antigo;
    update public.odo_fin_meses     set user_id = eu where user_id = antigo;
    update public.odo_fin_pagamentos set user_id = eu where user_id = antigo;
    update public.odo_fin_config    set user_id = eu where user_id = antigo;
    update public.odo_fin_comissoes set user_id = eu where user_id = antigo;
    update public.odo_fin_leituras  set dono_id = eu where dono_id = antigo;
    update public.odo_parceiros     set dono_id = eu where dono_id = antigo;
    update public.odo_membros       set dono_id = eu where dono_id = antigo;
    update public.odo_convites_emp  set dono_id = eu where dono_id = antigo and id <> c.id;
    update public.odo_contas_antigas set dono_id = eu where dono_id = antigo;
    insert into public.odo_contas_antigas (antigo_id, dono_id) values (antigo, eu) on conflict (antigo_id) do update set dono_id = eu;
    select nome into nm from public.odo_perfis where user_id = antigo;
    insert into public.odo_membros (dono_id, user_id, nome, cargo, ativo) values (eu, antigo, nm, c.cargo, true)
    on conflict (user_id) do update set dono_id = eu, cargo = excluded.cargo, ativo = true;
    update public.odo_empresas set papel = 'gestao' where user_id = eu and papel = 'func';
    perform set_config('odo.transferindo', '', true);
  end if;
  update public.odo_convites_emp set aceito_por = eu, aceito_em = now(), ativo = false where id = c.id;
  return jsonb_build_object('tipo', c.tipo, 'empresa', (select e.nome from public.odo_empresas e where e.user_id = (case when c.tipo = 'dono' then eu else c.dono_id end) limit 1));
end $$;
revoke all on function public.odo_convite_aceita(text) from public, anon;
grant execute on function public.odo_convite_aceita(text) to authenticated;

-- 6) A empresa em que a pessoa trabalha (nome e cargo) — para o aviso no topo
create or replace function public.odo_minha_equipe() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('dono_id', m.dono_id, 'cargo', m.cargo, 'empresa', (select e.nome from public.odo_empresas e where e.user_id = m.dono_id limit 1))
    from public.odo_membros m where m.user_id = auth.uid() and m.ativo limit 1;
$$;
revoke all on function public.odo_minha_equipe() from public, anon;
grant execute on function public.odo_minha_equipe() to authenticated;

-- 7) "Sou funcionário" na criação da empresa
alter table public.odo_empresas drop constraint if exists odo_empresas_papel_check;
alter table public.odo_empresas add constraint odo_empresas_papel_check check (papel in ('faz','gestao','func'));

select 'ok: 068 aplicada' as resultado;
