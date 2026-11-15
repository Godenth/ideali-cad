-- 085 · Tarefas: marcar como URGENTE. Pode rodar mais de uma vez.
alter table public.odo_tarefas add column if not exists urgente boolean not null default false;
