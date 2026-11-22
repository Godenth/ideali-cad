alter table public.odo_pedidos
  add column if not exists sem_comissao boolean not null default false,
  add column if not exists custo_desenho numeric(12,2);

comment on column public.odo_pedidos.sem_comissao is 'Pedido sem comissao: desenho executado pela i9 3D Lab';
comment on column public.odo_pedidos.custo_desenho is 'Valor do desenho/servico a descontar quando sem_comissao';
