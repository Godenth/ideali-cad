-- =====================================================================
-- Ideali CAD · Migração 002 · Clientes, preços, pedidos, pagamentos e arquivos
-- Requer a 001. Todas as tabelas têm dono (user_id), RLS e exclusão suave.
-- =====================================================================

-- ---------- Clientes ----------
create table public.clientes (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null default auth.uid() references auth.users(id) on delete cascade,
  nome          text not null check (char_length(nome) between 1 and 80),
  tipo          text not null default 'laboratorio' check (tipo in ('laboratorio','dentista')),
  telefone      text check (char_length(telefone) <= 30),
  email         text check (char_length(email) <= 120),
  observacoes   text check (char_length(observacoes) <= 500),
  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  deleted_at    timestamptz,
  unique (id, user_id)
);
create index clientes_user on public.clientes (user_id) where deleted_at is null;

-- ---------- Tipos de trabalho ----------
create table public.tipos_trabalho (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null default auth.uid() references auth.users(id) on delete cascade,
  nome          text not null check (char_length(nome) between 1 and 60),
  forma         text not null default 'elemento' check (forma in ('elemento','trabalho')),
  valor_padrao  numeric(10,2) not null default 0 check (valor_padrao >= 0),
  ativo         boolean not null default true,
  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  deleted_at    timestamptz,
  unique (id, user_id)
);
create index tipos_user on public.tipos_trabalho (user_id) where deleted_at is null;

-- ---------- Preço próprio de cada cliente ----------
create table public.precos_cliente (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null default auth.uid() references auth.users(id) on delete cascade,
  cliente_id       uuid not null,
  tipo_trabalho_id uuid not null,
  valor            numeric(10,2) not null check (valor >= 0),
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  deleted_at       timestamptz,
  unique (user_id, cliente_id, tipo_trabalho_id),
  foreign key (cliente_id, user_id) references public.clientes (id, user_id) on delete cascade,
  foreign key (tipo_trabalho_id, user_id) references public.tipos_trabalho (id, user_id) on delete cascade
);

-- ---------- Faixas de desconto por volume ----------
create table public.faixas_desconto (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null default auth.uid() references auth.users(id) on delete cascade,
  valor_minimo  numeric(10,2) not null check (valor_minimo >= 0),
  percentual    numeric(5,2) not null check (percentual > 0 and percentual <= 90),
  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  deleted_at    timestamptz
);

-- ---------- Pagamentos ----------
create table public.pagamentos (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null default auth.uid() references auth.users(id) on delete cascade,
  cliente_id       uuid not null,
  valor            numeric(10,2) not null check (valor > 0),
  data             date not null default current_date,
  forma            text not null default 'pix' check (forma in ('pix','transferencia','dinheiro','cartao')),
  comprovante_key  text,          -- caminho do comprovante no armazenamento privado
  observacoes      text check (char_length(observacoes) <= 200),
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  deleted_at       timestamptz,
  unique (id, user_id),
  foreign key (cliente_id, user_id) references public.clientes (id, user_id)
);
create index pagamentos_user_data on public.pagamentos (user_id, data) where deleted_at is null;

-- ---------- Pedidos ----------
create table public.pedidos (
  id                 uuid primary key default gen_random_uuid(),
  user_id            uuid not null default auth.uid() references auth.users(id) on delete cascade,
  numero             integer not null,
  cliente_id         uuid not null,
  paciente           text not null check (char_length(paciente) between 1 and 40),  -- só iniciais (LGPD)
  elementos          smallint[] not null default '{}',
  tipo_trabalho_id   uuid,
  cor                text check (char_length(cor) <= 20),
  observacoes        text check (char_length(observacoes) <= 500),
  valor              numeric(10,2) not null default 0 check (valor >= 0),
  urgente            boolean not null default false,
  status             text not null default 'entrada'
                       check (status in ('entrada','pendente','aprovacao','finalizado','arquivado')),
  pendencia_motivos  text[] not null default '{}',
  pendencia_obs      text check (char_length(pendencia_obs) <= 300),
  pendencia_desde    date,
  aprovacao_desde    date,
  ajustes            smallint not null default 0,
  recebido_em        date not null default current_date,
  prazo              date,
  enviado_em         date,          -- quando foi enviado ao cliente (arquivado)
  pago_em            date,
  pagamento_id       uuid,
  criado_em          timestamptz not null default now(),
  atualizado_em      timestamptz not null default now(),
  deleted_at         timestamptz,
  unique (id, user_id),
  unique (user_id, numero),
  check (elementos <@ array[11,12,13,14,15,16,17,18,21,22,23,24,25,26,27,28,
                            31,32,33,34,35,36,37,38,41,42,43,44,45,46,47,48]::smallint[]),
  foreign key (cliente_id, user_id) references public.clientes (id, user_id),
  foreign key (tipo_trabalho_id, user_id) references public.tipos_trabalho (id, user_id),
  foreign key (pagamento_id, user_id) references public.pagamentos (id, user_id)
);
create index pedidos_user_status on public.pedidos (user_id, status) where deleted_at is null;
create index pedidos_user_recebido on public.pedidos (user_id, recebido_em) where deleted_at is null;

-- Número sequencial por cadista (#1, #2, ...).
create or replace function public.tg_pedido_numero()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.numero is null or new.numero = 0 then
    select coalesce(max(numero), 0) + 1 into new.numero
      from public.pedidos where user_id = new.user_id;
  end if;
  return new;
end $$;

-- ---------- Arquivos (STL no Cloudflare R2 ou link externo) ----------
create table public.arquivos (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null default auth.uid() references auth.users(id) on delete cascade,
  pedido_id        uuid not null,
  origem           text not null check (origem in ('upload','link')),
  nome             text not null check (char_length(nome) between 1 and 160),
  storage_key      text,          -- chave do arquivo no R2 (só o servidor grava)
  url_externa      text check (url_externa ~* '^https://'),
  tamanho_original bigint check (tamanho_original >= 0),
  tamanho_zip      bigint check (tamanho_zip >= 0),
  removido_em      timestamptz,   -- apagado pela limpeza automática dos 60 dias
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  deleted_at       timestamptz,
  check ((origem = 'upload' and storage_key is not null and url_externa is null)
      or (origem = 'link' and url_externa is not null and storage_key is null)),
  foreign key (pedido_id, user_id) references public.pedidos (id, user_id)
);
create index arquivos_user on public.arquivos (user_id) where deleted_at is null;

-- O navegador não pode inventar tamanho nem caminho de arquivo enviado:
-- isso só o servidor (que confere a cota) pode gravar.
create or replace function public.tg_arquivo_protegido()
returns trigger language plpgsql set search_path = public as $$
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    if tg_op = 'INSERT' and new.origem = 'upload' then
      raise exception 'Envio de arquivo deve passar pelo servidor';
    end if;
    if tg_op = 'UPDATE' and (new.storage_key is distinct from old.storage_key
        or new.tamanho_zip is distinct from old.tamanho_zip
        or new.tamanho_original is distinct from old.tamanho_original
        or new.origem is distinct from old.origem
        or new.removido_em is distinct from old.removido_em) then
      raise exception 'Campos do arquivo só podem ser alterados pelo servidor';
    end if;
  end if;
  return new;
end $$;

-- Mantém o espaço usado da assinatura sempre certo.
create or replace function public.recalcula_uso(uid uuid)
returns void language sql security definer set search_path = public as $$
  update public.assinaturas set bytes_usados = coalesce((
    select sum(tamanho_zip) from public.arquivos
    where user_id = uid and origem = 'upload' and removido_em is null and deleted_at is null
  ), 0) where user_id = uid;
$$;
revoke all on function public.recalcula_uso(uuid) from public, anon, authenticated;

create or replace function public.tg_arquivo_uso()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.recalcula_uso(coalesce(new.user_id, old.user_id));
  return null;
end $$;
revoke all on function public.tg_arquivo_uso() from public, anon, authenticated;

-- ---------- Gatilhos comuns ----------
do $$
declare t text;
begin
  foreach t in array array['clientes','tipos_trabalho','precos_cliente','faixas_desconto','pagamentos','pedidos','arquivos'] loop
    execute format('create trigger %1$s_dono before insert or update on public.%1$s for each row execute function public.tg_dono()', t);
    execute format('create trigger %1$s_atualizado before update on public.%1$s for each row execute function public.tg_atualizado_em()', t);
  end loop;
end $$;

create trigger pedidos_numero before insert on public.pedidos
  for each row execute function public.tg_pedido_numero();
create trigger arquivos_protegido before insert or update on public.arquivos
  for each row execute function public.tg_arquivo_protegido();
create trigger arquivos_uso after insert or update or delete on public.arquivos
  for each row execute function public.tg_arquivo_uso();

-- ---------- Segurança (RLS) ----------
-- Ler: só o dono. Criar/editar: só o dono e com assinatura válida.
-- Nenhuma política de DELETE: "excluir" é preencher deleted_at (lixeira).
do $$
declare t text;
begin
  foreach t in array array['clientes','tipos_trabalho','precos_cliente','faixas_desconto','pagamentos','pedidos','arquivos'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('grant select, insert, update on public.%I to authenticated', t);
    execute format('create policy %1$s_ler on public.%1$s for select to authenticated using (user_id = auth.uid())', t);
    execute format('create policy %1$s_criar on public.%1$s for insert to authenticated with check (user_id = auth.uid() and public.pode_escrever())', t);
    execute format('create policy %1$s_editar on public.%1$s for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid() and public.pode_escrever())', t);
  end loop;
end $$;
