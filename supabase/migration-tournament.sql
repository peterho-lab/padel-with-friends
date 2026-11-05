-- Padel With Friends – Erweiterung: Turniere (fixe Termine mit eigener Teamgröße)
-- Im Supabase SQL-Editor ausführen. Kann mehrfach ausgeführt werden.
alter table slots add column if not exists kind text not null default 'match' check (kind in ('match', 'tournament'));
alter table slots add column if not exists title text;
alter table slots add column if not exists max_players int not null default 4 check (max_players between 1 and 40);

-- Regel "die ersten N reservieren": N ist jetzt die Teamgröße des Termins (4 bei normalen Matches)
create or replace function signups_before_insert() returns trigger language plpgsql as $$
declare n int; cap int;
begin
  select coalesce(max_players, 4) into cap from slots where id = new.slot_id for update;
  select count(*) into n from signups where slot_id = new.slot_id and kind = 'player';
  new.kind := case when n >= coalesce(cap, 4) then 'wait' else 'player' end;
  return new;
end $$;
