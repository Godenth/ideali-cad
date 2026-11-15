-- 084 · Tarefas: nome do cliente da sua lista (opcional). Pode rodar mais de uma vez.
alter table public.odo_tarefas add column if not exists cliente text;
alter table public.odo_tarefas drop constraint if exists odo_tarefas_cliente_tam;
alter table public.odo_tarefas add constraint odo_tarefas_cliente_tam check (cliente is null or char_length(cliente) <= 120);
