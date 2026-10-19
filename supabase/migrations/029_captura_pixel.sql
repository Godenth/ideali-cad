-- Página de captura: Pixel do Meta próprio por página (opcional). Só carrega com consentimento.
alter table public.captura_paginas add column if not exists pixel text check (pixel is null or pixel ~ '^[0-9]{10,20}$');
