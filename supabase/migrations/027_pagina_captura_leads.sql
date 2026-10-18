-- Página de captura para anúncios: cada cadista tem um link público (idealisystems.com/c/?u=SLUG).
-- O visitante deixa nome, tipo e WhatsApp; o lead cai na lista da Mika do dono e ele é levado ao WhatsApp do cadista.
-- Inserção pública só pela função "captura" (service_role), com limite por IP. O dono lê e apaga os próprios.
create table if not exists public.captura_paginas (
  user_id uuid primary key default auth.uid() references auth.users(id) on delete cascade,
  slug text not null unique check (slug ~ '^[a-z0-9][a-z0-9-]{2,39}$'),
  ativo boolean not null default true,
  titulo text check (char_length(titulo) <= 80),
  msg text check (char_length(msg) <= 300),
  criado_em timestamptz not null default now()
);
alter table public.captura_paginas enable row level security;
create policy captura_paginas_dono on public.captura_paginas for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create table if not exists public.captura_leads (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  nome text not null check (char_length(nome) between 2 and 60),
  tipo text check (tipo in ('dentista','protetico','outro')),
  telefone text not null check (telefone ~ '^[0-9]{10,11}$'),
  cidade text check (char_length(cidade) <= 60),
  origem text check (char_length(origem) <= 40),
  ip_hash text,
  criado_em timestamptz not null default now()
);
create index if not exists captura_leads_user on public.captura_leads(user_id, criado_em);
create index if not exists captura_leads_ip on public.captura_leads(ip_hash, criado_em);
alter table public.captura_leads enable row level security;
create policy captura_leads_ler on public.captura_leads for select to authenticated using (user_id = (select auth.uid()));
create policy captura_leads_apagar on public.captura_leads for delete to authenticated using (user_id = (select auth.uid()));
