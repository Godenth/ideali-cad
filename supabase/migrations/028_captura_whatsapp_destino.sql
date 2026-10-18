-- Página de captura: WhatsApp de destino próprio (opcional). Se vazio, usa o WhatsApp do perfil.
alter table public.captura_paginas add column if not exists wa text check (wa is null or wa ~ '^[0-9]{10,11}$');
