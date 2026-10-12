// Supabase falso para testar as telas sem internet. Registra cada gravação em window.__ops.
(function(){
  var U='dddddddd-0000-0000-0000-000000000004';
  var tabelas={perfis:[{user_id:U,nome:'Danilo',preferencias:{}}],assinaturas:[{user_id:U,plano:'basico',status:'teste',teste_ate:new Date(Date.now()+13*864e5).toISOString(),limite_bytes:5368709120,bytes_usados:0}],
    clientes:[],tipos_trabalho:[],precos_cliente:[],faixas_desconto:[],pagamentos:[],pedidos:[],arquivos:[]};
  window.__ops=[];var cbs=[],sessao=null;
  function Q(t){this.t=t;this.f=[];}
  Q.prototype.select=function(){this.op='select';return this;};
  Q.prototype.eq=function(c,v){this.f.push([c,v]);return this;};
  Q.prototype.range=function(){return this;};
  Q.prototype.maybeSingle=function(){this.single=true;return this;};
  Q.prototype.insert=function(r){this.op='insert';this.row=r;return this;};
  Q.prototype.update=function(r){this.op='update';this.row=r;return this;};
  Q.prototype.then=function(ok,ko){var me=this;return Promise.resolve().then(function(){
    var rows=tabelas[me.t];
    if(me.op==='insert'){window.__ops.push({op:'insert',t:me.t,row:JSON.parse(JSON.stringify(me.row))});rows.push(Object.assign({},me.row,{criado_em:new Date().toISOString()}));return {error:null};}
    var sel=rows.filter(function(r){return me.f.every(function(f){return r[f[0]]===f[1];});});
    if(me.op==='update'){window.__ops.push({op:'update',t:me.t,row:JSON.parse(JSON.stringify(me.row)),where:me.f});sel.forEach(function(r){Object.assign(r,me.row);});return {error:null};}
    return {data:me.single?(sel[0]||null):JSON.parse(JSON.stringify(sel)),error:null};
  }).then(ok,ko);};
  var client={
    from:function(t){return new Q(t);},
    auth:{
      onAuthStateChange:function(cb){cbs.push(cb);setTimeout(function(){cb('INITIAL_SESSION',sessao);},0);return {data:{subscription:{unsubscribe:function(){}}}};},
      getSession:function(){return Promise.resolve({data:{session:sessao}});},
      signInWithPassword:function(c){sessao={user:{id:U,email:c.email}};cbs.forEach(function(cb){cb('SIGNED_IN',sessao);});return Promise.resolve({data:{session:sessao},error:null});},
      signUp:function(c){return Promise.resolve({data:{session:null,user:{id:U}},error:null});},
      signOut:function(){sessao=null;cbs.forEach(function(cb){cb('SIGNED_OUT',null);});return Promise.resolve({error:null});},
      resetPasswordForEmail:function(){return Promise.resolve({error:null});},
      updateUser:function(){return Promise.resolve({error:null});}
    },
    rpc:function(n,a){window.__ops.push({op:'rpc',name:n,args:a});
      if(n==='sou_admin')return Promise.resolve({data:true,error:null});
      if(n==='admin_assinantes')return Promise.resolve({data:[
        {user_id:U,email:'dan@x.com',nome:'Danilo',telefone:'',cidade:'São Paulo',plano:'vitrine',status:'ativa',teste_ate:null,vence_em:null,limite_bytes:53687091200,bytes_usados:0,cadastro:new Date().toISOString(),ultimo_acesso:new Date().toISOString(),admin:true},
        {user_id:'eeee',email:'ana@lab.com',nome:'Ana Cadista',telefone:'(31) 9999-0000',cidade:'BH',plano:'basico',status:'teste',teste_ate:new Date(Date.now()+5*864e5).toISOString(),vence_em:null,limite_bytes:5368709120,bytes_usados:120000000,cadastro:new Date(Date.now()-9*864e5).toISOString(),ultimo_acesso:new Date().toISOString(),admin:false},
        {user_id:'ffff',email:'beto@cad.com',nome:'Beto',telefone:'',cidade:'',plano:'basico',status:'teste',teste_ate:new Date(Date.now()-2*864e5).toISOString(),vence_em:null,limite_bytes:5368709120,bytes_usados:0,cadastro:new Date(Date.now()-16*864e5).toISOString(),ultimo_acesso:null,admin:false}],error:null});
      return Promise.resolve({data:null,error:null});},
    functions:{invoke:function(n,o){window.__ops.push({op:'fn',name:n,body:o.body});if(n==='clima')return Promise.resolve({data:{temp:24.6,simbolo:window.__simbolo||'partlycloudy_day',min:17.2,max:28.9,atualizado:new Date().toISOString(),fonte:'MET Norway'},error:null});return Promise.resolve({data:{ok:true},error:null});}}
  };
  window.supabase={createClient:function(){return client;}};
  window.__U=U;
})();
