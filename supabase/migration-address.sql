-- Padel With Friends – Erweiterung: Adresse pro Halle (Karten-Link in Belegung und Termin)
-- Im Supabase SQL-Editor ausführen. Kann mehrfach ausgeführt werden.
alter table halls add column if not exists address text;
