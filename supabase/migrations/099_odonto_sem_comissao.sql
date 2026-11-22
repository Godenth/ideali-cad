alter table public.odo_pedidos
  add column if not exists sem_comissao boolean not null default false;

comment on column public.odo_pedidos.sem_comissao is 'Pedido nao gera comissao (ex.: design terceirizado i9 3D Lab)';
