-- Padel With Friends – Datenbankschema für Supabase (Postgres)
-- Einmal im Supabase SQL-Editor ausführen (Project → SQL Editor → New query → Run).

create extension if not exists pgcrypto;

-- Spieler: Stammspieler haben eine Farbe, Gäste nicht. Der Organisator hat admin = true.
create table if not exists players (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  short       text,
  email       text unique,
  color       text,
  regular     boolean not null default false,
  admin       boolean not null default false,
  created_at  timestamptz not null default now()
);

-- Slots: ein Termin auf einem Platz. court_idx = Platz-Index (0..2) bei Slots aus der Europahalle-Belegung.
create table if not exists slots (
  id          uuid primary key default gen_random_uuid(),
  date        date not null,
  time        text not null,              -- 'HH:MM'
  dur         int  not null default 120,  -- Minuten
  court       text not null,
  court_idx   int,
  created_by  uuid references players(id) on delete set null,
  created_at  timestamptz not null default now()
);
create index if not exists slots_date_idx on slots(date);

-- Eintragungen: kind = 'player' (einer der 4) oder 'wait' (Warteliste). Wird vom Trigger gesetzt.
create table if not exists signups (
  id          uuid primary key default gen_random_uuid(),
  slot_id     uuid not null references slots(id) on delete cascade,
  player_id   uuid not null references players(id) on delete cascade,
  kind        text not null default 'player' check (kind in ('player', 'wait')),
  created_at  timestamptz not null default now(),
  unique (slot_id, player_id)
);

-- "Ich hätte Zeit" pro Tag
create table if not exists availability (
  date        date not null,
  player_id   uuid not null references players(id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (date, player_id)
);

-- Platzbelegung der Halle pro Tag, aus dem Screenshot-Import.
-- grid = { "17": "ooX", ... }  je Stunde ein String, je Zeichen ein Platz: o frei, X gebucht, M unser Slot, . nicht buchbar
create table if not exists court_grid (
  date        date primary key,
  court       text not null default 'EUROPAHALLE',
  grid        jsonb not null,
  source      text,
  imported_at timestamptz not null default now()
);

-- Einstellungen, z. B. Anzeigefenster { "wd": 17, "we": 9 }
create table if not exists settings (
  key         text primary key,
  value       jsonb not null
);

-- Regel "die ersten 4 reservieren": beim Eintragen entscheidet die Datenbank, ob Spieler oder Warteliste.
create or replace function signups_before_insert() returns trigger language plpgsql as $$
declare n int;
begin
  perform 1 from slots where id = new.slot_id for update;   -- Slot sperren, damit zwei gleichzeitige Klicks nicht beide durchrutschen
  select count(*) into n from signups where slot_id = new.slot_id and kind = 'player';
  new.kind := case when n >= 4 then 'wait' else 'player' end;
  return new;
end $$;
drop trigger if exists trg_signups_before_insert on signups;
create trigger trg_signups_before_insert before insert on signups
  for each row execute function signups_before_insert();

-- Trägt sich ein Spieler aus, rückt der Erste der Warteliste nach.
create or replace function signups_after_delete() returns trigger language plpgsql as $$
begin
  if old.kind = 'player' then
    update signups set kind = 'player'
    where id = (select id from signups where slot_id = old.slot_id and kind = 'wait' order by created_at limit 1);
  end if;
  return old;
end $$;
drop trigger if exists trg_signups_after_delete on signups;
create trigger trg_signups_after_delete after delete on signups
  for each row execute function signups_after_delete();

-- Zugriff: Die App meldet Spieler nur per E-Mail an (ohne Passwort), deshalb arbeitet sie mit dem öffentlichen anon-Key.
-- Alle Tabellen sind für diesen Key les- und schreibbar. Schutz = Vertrauen im Freundeskreis plus unbekannte Adresse.
alter table players      enable row level security;
alter table slots        enable row level security;
alter table signups      enable row level security;
alter table availability enable row level security;
alter table court_grid   enable row level security;
alter table settings     enable row level security;

do $$ declare t text; begin
  foreach t in array array['players','slots','signups','availability','court_grid','settings'] loop
    execute format('drop policy if exists "app_all" on %I', t);
    execute format('create policy "app_all" on %I for all to anon, authenticated using (true) with check (true)', t);
  end loop;
end $$;

-- Live-Updates: Änderungen sofort bei allen Spielern anzeigen
do $$ declare t text; begin
  foreach t in array array['players','slots','signups','availability','court_grid','settings'] loop
    begin
      execute format('alter publication supabase_realtime add table %I', t);
    exception when duplicate_object then null; end;
  end loop;
end $$;

-- Spieler und Einstellungen: siehe supabase/seed.sql (lokal, nicht im Repository)
