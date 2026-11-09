# Padel With Friends

Kleine Web-App, mit der sich eine Gruppe von Padel-Freunden zum Spielen verabredet.
Wochenansicht, Slots mit 4 Plätzen, "die ersten 4 reservieren", Warteliste, Login nur per E-Mail.
Der Organisator importiert die Platzbelegung der EUROPAHALLE per Screenshot, die App erkennt freie Stunden selbst.

## Aufbau

| Teil | Technik |
|---|---|
| Oberfläche | eine statische Seite, `index.html` (kein Build-Schritt) |
| Daten | Supabase (Postgres + Realtime), Schema in `supabase/schema.sql` |
| Hosting | GitHub Pages, eigene Domain über `CNAME` |

## Einrichten

1. Supabase-Projekt anlegen (kostenlos): https://supabase.com → New project.
2. Im Supabase SQL-Editor zuerst `supabase/schema.sql` ausführen, dann die lokale `supabase/seed.sql` (Spieler).
3. In `config.js` die Project URL und den anon-Key eintragen (Project Settings → API).
4. Seite veröffentlichen: GitHub Pages aus dem `main`-Branch, Ordner `/` (root).
4b. Teams: danach `supabase/migration-groups.sql` ausführen (legt TEAM KITE mit den bestehenden Daten und TEAM 123 an). Jedes Team hat einen eigenen Link, z. B. `padelwithfriends.at/#kite`.
4c. Hallen: danach `supabase/migration-halls.sql` ausführen. Hallen (Name, Plätze) legt der Organisator in der App an und ordnet sie seinem Team zu; der Import fragt nach der Halle.
4d. Weitere Erweiterungen, jeweils einmal ausführen: `migration-cancel.sql` (Absagen), `migration-comments.sql` (Kommentare), `migration-avail-part.sql` (Vormittag/Nachmittag), `migration-tournament.sql` (Turniere), `migration-reserved.sql` (Haken „Platz ist fix reserviert“), `migration-singles.sql` (Einzelplätze mit 2 Spielern, pro Halle im Hallen-Dialog markierbar), `migration-address.sql` (Adresse pro Halle, Karten-Link).
5. Domain `padelwithfriends.at`: A-Records auf 185.199.108.153, 185.199.109.153, 185.199.110.153, 185.199.111.153 und CNAME `www` → `peterho-lab.github.io`; die Datei `CNAME` im Repository trägt die Domain bei GitHub Pages ein.

## Sicherheit

Es gibt bewusst kein Passwort. Wer eine eingetragene E-Mail-Adresse kennt, kann sich als diese Person eintragen.
Die Datenbank ist für den öffentlichen anon-Key les- und schreibbar. Das passt für einen Freundeskreis, nicht für mehr.
Persönliche Daten (E-Mail-Adressen) liegen nur in der Datenbank, nicht im Repository (`supabase/seed.sql` ist in `.gitignore`).

## Dateien

- `index.html` – die App
- `config.js` – Verbindung zur Datenbank
- `assets/` – Logos und Bälle
- `supabase/schema.sql` – Tabellen, Trigger (4-Spieler-Regel, Warteliste rückt nach), Zugriffsregeln
- `design/padel-mockup.html` – klickbarer Entwurf ohne Datenbank (Demo-Daten im Browser)
