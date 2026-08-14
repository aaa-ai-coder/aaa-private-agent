-- API Keys table for managing multiple AI provider keys.
-- Each user can have multiple API keys stored securely.
-- id is a client-supplied string (e.g. key_<timestamp>_<rand>).

create table if not exists public.api_keys (
  id text primary key,
  user_id uuid references public.profiles(id) on delete cascade not null,
  name text not null default '',
  provider text not null default 'custom',
  base_url text not null,
  model text not null default '',
  api_key text not null,
  is_active boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Each user can have only one active key at a time
create unique index if not exists idx_api_keys_active_per_user
  on public.api_keys(user_id) where is_active = true;

alter table public.api_keys enable row level security;

-- Users can fully manage their own keys
drop policy if exists "Users can manage own API keys" on public.api_keys;
create policy "Users can manage own API keys" on public.api_keys
  for all to anon, authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Auto-update updated_at timestamp
create or replace function public.update_api_keys_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists set_api_keys_updated_at on public.api_keys;
create trigger set_api_keys_updated_at
  before update on public.api_keys
  for each row execute function public.update_api_keys_updated_at();
