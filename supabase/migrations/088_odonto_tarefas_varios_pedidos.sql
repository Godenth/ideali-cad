-- 088 · Tarefas: ligar a tarefa a VÁRIOS pedidos do cliente. Lista [{id, txt}] (até 60). Pode rodar mais de uma vez.
alter table public.odo_tarefas add column if not exists pedidos jsonb;
alter table public.odo_tarefas drop constraint if exists odo_tarefas_pedidos_ok;
alter table public.odo_tarefas add constraint odo_tarefas_pedidos_ok check (pedidos is null or (jsonb_typeof(pedidos) = 'array' and jsonb_array_length(pedidos) <= 60 and pg_column_size(pedidos) < 20000));
