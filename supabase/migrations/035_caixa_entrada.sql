-- Ideali CAD · Migração 035 · "Envie seu trabalho" e Caixa de entrada
-- Cada cadista tem um link próprio (pode desligar ou trocar). Dentistas, laboratórios e clínicas abrem o link,
-- preenchem os dados do caso e enviam. O envio cai na Caixa de entrada do cadista.
-- Por enquanto só aceita LINKS de arquivos (Drive, WeTransfer…): o envio de anexos para o armazenamento ainda não está liberado.
-- Quem envia nunca lê nada da conta: só consegue gravar um envio, por uma função que confere o link e limita a quantidade.

-- 1) Link de envio do cadista
create table if not exists public.caixa_links (
  user_id   uuid primary key default auth.uid() references auth.users(id) on delete cascade,
  token     text not null unique check (token ~ '^[A-Za-z0-9_-]{24,64}$'),
  ativo     boolean not null default true,
  criado_em timestamptz not null default now()
);
alter table public.caixa_links enable row level security;
create policy caixa_links_dono on public.caixa_links for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
revoke all on public.caixa_links from anon;
grant select, insert, update, delete on public.caixa_links to authenticated;

-- 2) Caixa de entrada
create table if not exists public.caixa_entrada (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  origem      text not null default 'link' check (origem in ('link','email')),
  tipo        text check (tipo is null or tipo in ('Dentista','Laboratório','Clínica')),
  remetente   text not null check (length(remetente) between 2 and 80),
  doutor      text check (doutor is null or length(doutor) <= 80),
  telefone    text check (telefone is null or telefone ~ '^[0-9]{10,13}$'),
  paciente    text check (paciente is null or length(paciente) <= 40),
  descricao   text not null check (length(descricao) between 3 and 2000),
  links       jsonb not null default '[]'::jsonb check (jsonb_typeof(links) = 'array' and jsonb_array_length(links) <= 5 and pg_column_size(links) <= 4000),
  status      text not null default 'novo' check (status in ('novo','lido','aprovado','recusado')),
  pedido_id   text,
  criado_em   timestamptz not null default now()
);
create index if not exists caixa_entrada_user_idx on public.caixa_entrada(user_id, criado_em desc);
alter table public.caixa_entrada enable row level security;
create policy caixa_sel on public.caixa_entrada for select to authenticated using (user_id = (select auth.uid()));
create policy caixa_upd on public.caixa_entrada for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy caixa_del on public.caixa_entrada for delete to authenticated using (user_id = (select auth.uid()));
revoke all on public.caixa_entrada from anon;
grant select, update, delete on public.caixa_entrada to authenticated;   -- sem insert direto: só pela função abaixo

-- 3) Página pública: nome do cadista para o cabeçalho (só se o link estiver ligado)
create or replace function public.caixa_info(tk text)
returns table (nome text) language sql stable security definer set search_path = public as $$
  select coalesce(nullif(split_part(p.nome, ' ', 1), ''), 'o cadista')
    from public.caixa_links l left join public.perfis p on p.user_id = l.user_id
   where l.token = tk and l.ativo
   limit 1;
$$;
revoke all on function public.caixa_info(text) from public;
grant execute on function public.caixa_info(text) to anon, authenticated;

-- 4) Página pública: enviar um trabalho
create or replace function public.caixa_enviar(tk text, d jsonb)
returns text language plpgsql security definer set search_path = public as $$
declare dono uuid; n int; lk jsonb := '[]'::jsonb; x jsonb; tel text;
begin
  select l.user_id into dono from public.caixa_links l where l.token = tk and l.ativo;
  if dono is null then return 'link_invalido'; end if;
  if coalesce(d->>'site','') <> '' then return 'ok'; end if;                       -- campo-armadilha para robôs
  select count(*) into n from public.caixa_entrada c where c.user_id = dono and c.origem = 'link' and c.criado_em > now() - interval '1 day';
  if n >= 30 then return 'limite'; end if;
  if jsonb_typeof(d->'links') = 'array' then
    for x in select * from jsonb_array_elements(d->'links') limit 5 loop
      if jsonb_typeof(x) = 'string' and (x #>> '{}') ~* '^https://[^\s<>"]{4,500}$' then lk := lk || jsonb_build_array(x #>> '{}'); end if;
    end loop;
  end if;
  tel := nullif(regexp_replace(coalesce(d->>'telefone',''), '\D', '', 'g'), '');
  if tel is not null and tel !~ '^[0-9]{10,13}$' then tel := null; end if;
  insert into public.caixa_entrada (user_id, origem, tipo, remetente, doutor, telefone, paciente, descricao, links)
  values (dono, 'link',
          case when d->>'tipo' in ('Dentista','Laboratório','Clínica') then d->>'tipo' end,
          left(trim(coalesce(d->>'remetente','')), 80),
          nullif(left(trim(coalesce(d->>'doutor','')), 80), ''),
          tel,
          nullif(left(trim(coalesce(d->>'paciente','')), 40), ''),
          left(trim(coalesce(d->>'descricao','')), 2000),
          lk);
  return 'ok';
exception when check_violation then return 'dados_invalidos';
end $$;
revoke all on function public.caixa_enviar(text, jsonb) from public;
grant execute on function public.caixa_enviar(text, jsonb) to anon, authenticated;
