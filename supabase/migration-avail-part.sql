-- Padel With Friends – Erweiterung: "Ich hätte Zeit" mit Vormittag / Nachmittag / ganzer Tag
-- Im Supabase SQL-Editor ausführen. Kann mehrfach ausgeführt werden.
alter table availability add column if not exists part text not null default 'all' check (part in ('all', 'am', 'pm'));
