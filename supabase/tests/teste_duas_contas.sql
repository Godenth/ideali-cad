-- Teste de isolamento entre duas contas (A e B). Cada bloco imprime OK ou FALHOU.
\set ON_ERROR_STOP off
\pset tuples_only on
insert into auth.users (id,email,raw_user_meta_data) values
 ('aaaaaaaa-0000-0000-0000-000000000001','a@teste.com','{"nome":"Cadista A"}'),
 ('bbbbbbbb-0000-0000-0000-000000000002','b@teste.com','{"nome":"Cadista B"}');
select case when count(*)=2 then 'OK  cadastro cria perfil e teste de 14 dias' else 'FALHOU cadastro' end from public.assinaturas where status='teste' and teste_ate > now()+interval '13 days';

-- ===== Conta A cria dados =====
set role authenticated; select set_config('request.jwt.claim.sub','aaaaaaaa-0000-0000-0000-000000000001',false), set_config('request.jwt.claim.role','authenticated',false) \g /dev/null
insert into public.clientes (id,nome,tipo) values ('c0000000-0000-0000-0000-00000000000a','Lab. do A','laboratorio');
insert into public.tipos_trabalho (id,nome,forma,valor_padrao) values ('d0000000-0000-0000-0000-00000000000a','Coroa','elemento',90);
insert into public.precos_cliente (cliente_id,tipo_trabalho_id,valor) values ('c0000000-0000-0000-0000-00000000000a','d0000000-0000-0000-0000-00000000000a',80);
insert into public.pedidos (id,cliente_id,paciente,elementos,tipo_trabalho_id,valor) values ('e0000000-0000-0000-0000-00000000000a','c0000000-0000-0000-0000-00000000000a','M.A.S.','{11,21}','d0000000-0000-0000-0000-00000000000a',160);
insert into public.pedidos (cliente_id,paciente) values ('c0000000-0000-0000-0000-00000000000a','J.C.');
select case when (select array_agg(numero order by numero) from public.pedidos)='{1,2}' then 'OK  numeração #1, #2 por cadista' else 'FALHOU numeração' end;
insert into public.arquivos (pedido_id,origem,nome,url_externa) values ('e0000000-0000-0000-0000-00000000000a','link','drive','https://drive.google.com/x');
select 'OK  A vê '||count(*)||' cliente(s), '||(select count(*) from public.pedidos)||' pedido(s)' from public.clientes;

-- Tentativas proibidas da própria conta A
do $$ begin insert into public.arquivos (pedido_id,origem,nome,storage_key,tamanho_zip) values ('e0000000-0000-0000-0000-00000000000a','upload','falso.zip','x/y',1); raise notice 'FALHOU: navegador conseguiu registrar upload'; exception when others then raise notice 'OK  navegador não registra upload sem passar pelo servidor'; end $$;
do $$ begin insert into public.pedidos (cliente_id,paciente,elementos) values ('c0000000-0000-0000-0000-00000000000a','X','{99}'); raise notice 'FALHOU: aceitou dente 99'; exception when others then raise notice 'OK  rejeita dente inexistente (99)'; end $$;
do $$ begin update public.assinaturas set status='ativa'; raise notice 'FALHOU: alterou a própria assinatura'; exception when others then raise notice 'OK  cadista não altera a própria assinatura'; end $$;
do $$ begin delete from public.clientes; raise notice 'FALHOU: apagou de verdade'; exception when others then raise notice 'OK  não existe DELETE (só lixeira)'; end $$;
update public.clientes set deleted_at=now() where id='c0000000-0000-0000-0000-00000000000a';
select case when deleted_at is not null then 'OK  excluir = mandar para a lixeira' else 'FALHOU lixeira' end from public.clientes;
update public.clientes set deleted_at=null;
do $$ declare n int; begin update public.clientes set user_id='bbbbbbbb-0000-0000-0000-000000000002'; select count(*) into n from public.clientes where user_id=auth.uid(); if n=1 then raise notice 'OK  não dá para passar o cliente para outra conta'; else raise notice 'FALHOU troca de dono'; end if; end $$;

-- ===== Conta B tenta ver e mexer nos dados de A =====
select set_config('request.jwt.claim.sub','bbbbbbbb-0000-0000-0000-000000000002',false) \g /dev/null
select case when (select count(*) from public.clientes)+(select count(*) from public.pedidos)+(select count(*) from public.tipos_trabalho)+(select count(*) from public.precos_cliente)+(select count(*) from public.arquivos)=0 then 'OK  B não enxerga nada de A' else 'FALHOU B vê dados de A' end;
select case when (select count(*) from public.perfis)=1 and (select nome from public.perfis)='Cadista B' then 'OK  B só vê o próprio perfil' else 'FALHOU perfil' end;
select case when (select count(*) from public.assinaturas)=1 then 'OK  B só vê a própria assinatura' else 'FALHOU assinatura' end;
update public.clientes set nome='hackeado';
update public.pedidos set valor=0;
do $$ begin insert into public.pedidos (cliente_id,paciente) values ('c0000000-0000-0000-0000-00000000000a','Z'); raise notice 'FALHOU: B criou pedido no cliente de A'; exception when others then raise notice 'OK  B não consegue usar cliente de A num pedido'; end $$;
do $$ begin insert into public.clientes (nome,user_id) values ('intruso','aaaaaaaa-0000-0000-0000-000000000001'); if exists(select 1 from public.clientes where nome='intruso' and user_id=auth.uid()) then raise notice 'OK  B não grava na conta de A (o dono vira B)'; else raise notice 'FALHOU'; end if; exception when others then raise notice 'OK  B não grava na conta de A'; end $$;

-- ===== Volta para A e confere que nada mudou =====
select set_config('request.jwt.claim.sub','aaaaaaaa-0000-0000-0000-000000000001',false) \g /dev/null
select case when nome='Lab. do A' then 'OK  edição de B não afetou A' else 'FALHOU B alterou A' end from public.clientes;
select case when (select valor from public.pedidos where numero=1)=160 then 'OK  valor do pedido de A intacto' else 'FALHOU' end;

-- ===== Servidor registra upload e a cota é recalculada =====
reset role; set role service_role; select set_config('request.jwt.claim.role','service_role',false) \g /dev/null
insert into public.arquivos (user_id,pedido_id,origem,nome,storage_key,tamanho_original,tamanho_zip) values ('aaaaaaaa-0000-0000-0000-000000000001','e0000000-0000-0000-0000-00000000000a','upload','MAS.zip','aaaaaaaa/e0/MAS.zip',48000000,11600000);
select case when bytes_usados=11600000 then 'OK  espaço usado atualizado (11,6 MB)' else 'FALHOU uso: '||bytes_usados end from public.assinaturas where user_id='aaaaaaaa-0000-0000-0000-000000000001';

-- ===== Assinatura vencida bloqueia gravação, mas mantém leitura =====
update public.assinaturas set status='vencida' where user_id='aaaaaaaa-0000-0000-0000-000000000001';
reset role; set role authenticated; select set_config('request.jwt.claim.sub','aaaaaaaa-0000-0000-0000-000000000001',false), set_config('request.jwt.claim.role','authenticated',false) \g /dev/null
do $$ begin insert into public.clientes (nome) values ('novo'); raise notice 'FALHOU: vencida conseguiu gravar'; exception when others then raise notice 'OK  vencida não grava'; end $$;
select case when count(*)=1 then 'OK  vencida continua lendo os dados' else 'FALHOU leitura' end from public.clientes;
reset role;
