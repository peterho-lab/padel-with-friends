-- Padel With Friends – Erweiterung: Einzelplätze (Single Courts, 2 Spieler)
-- Im Supabase SQL-Editor ausführen. Kann mehrfach ausgeführt werden.
-- singles = Liste der Platz-Positionen (0 = erster Platz im Buchungsplan), die Einzelplätze sind.
alter table halls add column if not exists singles int[] not null default '{}';
