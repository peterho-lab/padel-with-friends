-- Padel With Friends – Erweiterung: mehrere Teams (Gruppen)
-- Einmal im Supabase SQL-Editor ausführen, nachdem schema.sql und seed.sql gelaufen sind.
-- Bestehende Daten wandern in das erste Team "TEAM KITE". Kann gefahrlos mehrfach ausgeführt werden.

-- Teams: eigener Link (slug), Name, Halle, Anzeigefenster
create table if not exists groups (
  id          uuid primary key default gen_random_uuid(),
  slug        text unique not null,
  name        text not null,
  hall        text not null default 'EUROPAHALLE',
  window      jsonb not null default '{"wd": 17, "we": 9}',
  created_at  timestamptz not null default now()
);

-- Mitgliedschaft: wer gehört zu welchem Team, Rolle member oder organizer
create table if not exists memberships (
  group_id    uuid not null references groups(id) on delete cascade,
  player_id   uuid not null references players(id) on delete cascade,
  role        text not null default 'member' check (role in ('member', 'organizer')),
  created_at  timestamptz not null default now(),
  primary key (group_id, player_id)
);

insert into groups (slug, name) values ('kite', 'TEAM KITE'), ('team123', 'TEAM 123')
on conflict (slug) do nothing;

-- Slots, Verfügbarkeit und Belegung gehören zu einem Team
alter table slots        add column if not exists group_id uuid references groups(id) on delete cascade;
alter table availability add column if not exists group_id uuid references groups(id) on delete cascade;
alter table court_grid   add column if not exists group_id uuid references groups(id) on delete cascade;

update slots        set group_id = (select id from groups where slug = 'kite') where group_id is null;
update availability set group_id = (select id from groups where slug = 'kite') where group_id is null;
update court_grid   set group_id = (select id from groups where slug = 'kite') where group_id is null;

alter table slots        alter column group_id set not null;
alter table availability alter column group_id set not null;
alter table court_grid   alter column group_id set not null;

alter table availability drop constraint if exists availability_pkey;
alter table availability add primary key (group_id, date, player_id);
alter table court_grid   drop constraint if exists court_grid_pkey;
alter table court_grid   add primary key (group_id, date);
create index if not exists slots_group_date_idx on slots(group_id, date);

-- Alle bisherigen Spieler sind Mitglieder von TEAM KITE, der Admin ist dort Organisator
insert into memberships (group_id, player_id, role)
select g.id, p.id, case when p.admin then 'organizer' else 'member' end
from groups g, players p where g.slug = 'kite'
on conflict do nothing;

-- Der Admin ist auch in TEAM 123 Organisator
insert into memberships (group_id, player_id, role)
select g.id, p.id, 'organizer' from groups g, players p where g.slug = 'team123' and p.admin
on conflict do nothing;

-- Bisheriges Anzeigefenster übernehmen
update groups set window = coalesce((select value from settings where key = 'window'), window) where slug = 'kite';

-- Zugriff und Live-Updates für die neuen Tabellen
alter table groups      enable row level security;
alter table memberships enable row level security;
do $$ declare t text; begin
  foreach t in array array['groups', 'memberships'] loop
    execute format('drop policy if exists "app_all" on %I', t);
    execute format('create policy "app_all" on %I for all to anon, authenticated using (true) with check (true)', t);
    begin
      execute format('alter publication supabase_realtime add table %I', t);
    exception when duplicate_object then null; end;
  end loop;
end $$;
