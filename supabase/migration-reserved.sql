-- Padel With Friends – Erweiterung: Haken "Platz ist fix reserviert" pro Termin
-- Im Supabase SQL-Editor ausführen. Kann mehrfach ausgeführt werden.
alter table slots add column if not exists reserved boolean not null default false;
