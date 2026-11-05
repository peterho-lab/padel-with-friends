-- Padel With Friends – Erweiterung: Termine absagen (für alle Spieler möglich)
-- Im Supabase SQL-Editor ausführen. Kann mehrfach ausgeführt werden.
alter table slots add column if not exists cancelled_at timestamptz;
alter table slots add column if not exists cancelled_by uuid references players(id) on delete set null;
