-- Padel With Friends – Erweiterung: Kommentare unter Terminen
-- Im Supabase SQL-Editor ausführen. Kann mehrfach ausgeführt werden.
create table if not exists comments (
  id          uuid primary key default gen_random_uuid(),
  slot_id     uuid not null references slots(id) on delete cascade,
  player_id   uuid references players(id) on delete set null,
  text        text not null check (char_length(text) <= 240),
  created_at  timestamptz not null default now()
);
create index if not exists comments_slot_idx on comments(slot_id);
alter table comments enable row level security;
drop policy if exists "app_all" on comments;
create policy "app_all" on comments for all to anon, authenticated using (true) with check (true);
do $$ begin
  alter publication supabase_realtime add table comments;
exception when duplicate_object then null; end $$;
