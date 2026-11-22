alter table public.odo_pedidos
  add column if not exists aguardando_pendencia boolean not null default false,
  add column if not exists motivo_pendencia text;

comment on column public.odo_pedidos.aguardando_pendencia is 'Pedido travado aguardando retorno do dentista/clinica';
comment on column public.odo_pedidos.motivo_pendencia is 'Motivo curto da pendencia exibido no card';
