-- Padel With Friends – Erweiterung: Hallen (mehrere pro Team, vom Organisator anlegbar)
-- Im Supabase SQL-Editor ausführen, nachdem migration-groups.sql gelaufen ist. Kann mehrfach ausgeführt werden.

create table if not exists halls (
  id          uuid primary key default gen_random_uuid(),
  name        text unique not null,
  courts      int  not null default 3 check (courts between 1 and 12),
  first_hour  int  not null default 7,
  last_hour   int  not null default 22,
  created_at  timestamptz not null default now()
);
insert into halls (name, courts) values ('EUROPAHALLE', 3) on conflict (name) do nothing;

-- Welche Hallen ein Team nutzt
create table if not exists group_halls (
  group_id    uuid not null references groups(id) on delete cascade,
  hall_id     uuid not null references halls(id) on delete cascade,
  primary key (group_id, hall_id)
);
insert into group_halls (group_id, hall_id)
select g.id, h.id from groups g join halls h on upper(h.name) = upper(g.hall)
on conflict do nothing;

-- Belegung gehört zu Team + Halle + Tag
alter table court_grid add column if not exists hall_id uuid references halls(id) on delete cascade;
update court_grid c set hall_id = h.id from halls h where c.hall_id is null and upper(h.name) = upper(c.court);
update court_grid set hall_id = (select id from halls where name = 'EUROPAHALLE') where hall_id is null;
alter table court_grid alter column hall_id set not null;
alter table court_grid drop constraint if exists court_grid_pkey;
alter table court_grid add primary key (group_id, hall_id, date);

-- Slots kennen ihre Halle (für die gelbe Markierung in der Belegung)
alter table slots add column if not exists hall_id uuid references halls(id) on delete set null;
update slots s set hall_id = h.id from halls h where s.hall_id is null and upper(s.court) like upper(h.name) || '%';

-- Zugriff und Live-Updates
alter table halls       enable row level security;
alter table group_halls enable row level security;
do $$ declare t text; begin
  foreach t in array array['halls', 'group_halls'] loop
    execute format('drop policy if exists "app_all" on %I', t);
    execute format('create policy "app_all" on %I for all to anon, authenticated using (true) with check (true)', t);
    begin
      execute format('alter publication supabase_realtime add table %I', t);
    exception when duplicate_object then null; end;
  end loop;
end $$;
