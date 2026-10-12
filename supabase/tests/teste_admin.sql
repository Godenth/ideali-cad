\pset tuples_only on
insert into auth.users(id,email,raw_user_meta_data) values
 ('aaaaaaaa-0000-0000-0000-00000000000a','dono@x.com','{"nome":"Dono"}'),
 ('bbbbbbbb-0000-0000-0000-00000000000b','cadista@x.com','{"nome":"Cadista"}');
insert into public.admins(user_id) values ('aaaaaaaa-0000-0000-0000-00000000000a');
set role authenticated;
-- cadista comum
select set_config('request.jwt.claim.sub','bbbbbbbb-0000-0000-0000-00000000000b',false) \g /dev/null
select case when not public.sou_admin() then 'OK cadista não é admin' else 'FALHOU' end;
do $$ begin perform * from public.admin_assinantes(); raise notice 'FALHOU cadista listou assinantes'; exception when others then raise notice 'OK cadista não lista assinantes'; end $$;
do $$ begin perform public.admin_altera_assinatura('bbbbbbbb-0000-0000-0000-00000000000b','ativa'); raise notice 'FALHOU cadista se ativou'; exception when others then raise notice 'OK cadista não se ativa sozinho'; end $$;
do $$ begin insert into public.admins values ('bbbbbbbb-0000-0000-0000-00000000000b'); raise notice 'FALHOU virou admin'; exception when others then raise notice 'OK cadista não se promove a admin'; end $$;
-- admin
select set_config('request.jwt.claim.sub','aaaaaaaa-0000-0000-0000-00000000000a',false) \g /dev/null
select case when public.sou_admin() then 'OK dono é admin' else 'FALHOU' end;
select case when count(*)=2 then 'OK admin lista 2 assinantes' else 'FALHOU' end from public.admin_assinantes();
select public.admin_altera_assinatura('bbbbbbbb-0000-0000-0000-00000000000b','ativa','plus',now()+interval '30 days',null,10737418240) \g /dev/null
reset role;
select case when status='ativa' and plano='plus' and limite_bytes=10737418240 then 'OK admin ativou plano Plus 10 GB' else 'FALHOU' end from public.assinaturas where user_id='bbbbbbbb-0000-0000-0000-00000000000b';
select case when count(*)=1 then 'OK alteração registrada no histórico' else 'FALHOU' end from public.admin_log;
set role authenticated;
select set_config('request.jwt.claim.sub','aaaaaaaa-0000-0000-0000-00000000000a',false) \g /dev/null
-- admin NÃO vê dados de trabalho do cadista
select set_config('request.jwt.claim.sub','bbbbbbbb-0000-0000-0000-00000000000b',false) \g /dev/null
insert into public.clientes(nome) values ('Cliente do cadista');
select set_config('request.jwt.claim.sub','aaaaaaaa-0000-0000-0000-00000000000a',false) \g /dev/null
select case when count(*)=0 then 'OK admin não vê clientes/pedidos dos cadistas (LGPD)' else 'FALHOU' end from public.clientes;
reset role;
