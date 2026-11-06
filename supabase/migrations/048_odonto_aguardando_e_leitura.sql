-- =====================================================================
-- 048 · Ideali Odonto
--  1) Pedidos: nova situação "aguardando informação" (CAD parado esperando o cliente).
--  2) Prova de leitura da Inove: quando a conta espelho ABRE o comprovante de um pagamento
--     e quando CONFIRMA que viu. É o único dado que a Inove grava, e só nesta tabela:
--     ela nunca altera os dados do dono.
-- =====================================================================
alter table public.odo_pedidos drop constraint if exists odo_pedidos_status_check;
alter table public.odo_pedidos add constraint odo_pedidos_status_check
  check (status in ('orcamento','aguardando','desenho','producao','finalizado','entregue','cancelado'));

create table if not exists public.odo_fin_leituras (
  id            uuid primary key default gen_random_uuid(),
  dono_id       uuid not null references auth.users(id) on delete cascade,
  pagamento_id  uuid not null references public.odo_fin_pagamentos(id) on delete cascade,
  parceiro_id   uuid not null default auth.uid() references auth.users(id) on delete cascade,
  aberto_em     timestamptz,
  confirmado_em timestamptz,
  criado_em     timestamptz not null default now(),
  unique (pagamento_id, parceiro_id)
);
alter table public.odo_fin_leituras enable row level security;
drop policy if exists odo_fin_leit_dono on public.odo_fin_leituras;
create policy odo_fin_leit_dono on public.odo_fin_leituras for select to authenticated
  using (dono_id = (select auth.uid()));
drop policy if exists odo_fin_leit_parc_ler on public.odo_fin_leituras;
create policy odo_fin_leit_parc_ler on public.odo_fin_leituras for select to authenticated
  using (parceiro_id = (select auth.uid()));
drop policy if exists odo_fin_leit_parc_novo on public.odo_fin_leituras;
create policy odo_fin_leit_parc_novo on public.odo_fin_leituras for insert to authenticated
  with check (parceiro_id = (select auth.uid()) and public.odo_parceiro_de(dono_id));
drop policy if exists odo_fin_leit_parc_muda on public.odo_fin_leituras;
create policy odo_fin_leit_parc_muda on public.odo_fin_leituras for update to authenticated
  using (parceiro_id = (select auth.uid()) and public.odo_parceiro_de(dono_id))
  with check (parceiro_id = (select auth.uid()) and public.odo_parceiro_de(dono_id));
revoke all on public.odo_fin_leituras from anon;

-- o pagamento tem que ser do dono; o horário é sempre o do servidor; confirmar só depois de abrir; não volta atrás
create or replace function public.odo_fin_leit_trava() returns trigger language plpgsql as $$
begin
  if not exists (select 1 from public.odo_fin_pagamentos p where p.id = new.pagamento_id and p.user_id = new.dono_id) then
    raise exception 'pagamento inválido'; end if;
  if tg_op = 'UPDATE' then
    new.dono_id := old.dono_id; new.pagamento_id := old.pagamento_id; new.parceiro_id := old.parceiro_id; new.criado_em := old.criado_em;
    new.aberto_em := coalesce(old.aberto_em, case when new.aberto_em is not null then now() end);
    new.confirmado_em := coalesce(old.confirmado_em, case when new.confirmado_em is not null then now() end);
  else
    new.aberto_em := case when new.aberto_em is not null then now() end;
    new.confirmado_em := case when new.confirmado_em is not null then now() end;
  end if;
  if new.confirmado_em is not null and new.aberto_em is null then raise exception 'abra o comprovante antes de confirmar'; end if;
  return new; end $$;
drop trigger if exists odo_fin_leit_trava on public.odo_fin_leituras;
create trigger odo_fin_leit_trava before insert or update on public.odo_fin_leituras for each row execute function public.odo_fin_leit_trava();

select 'ok: 048 aplicada' as resultado;
