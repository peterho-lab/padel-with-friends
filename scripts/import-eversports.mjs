// Padel With Friends – automatischer Import der Platzbelegung von Eversports-Hallen
//
// Liest den öffentlichen Belegungsplan (ohne Login) und schreibt ihn als court_grid in Supabase,
// für jedes Team, das die Halle unter "Hallen" angehakt hat. Läuft per GitHub Actions (siehe
// .github/workflows/import-eversports.yml) oder von Hand:  node scripts/import-eversports.mjs [--dry]
//
// Umgebung: SUPABASE_URL und SUPABASE_KEY (der öffentliche Publishable Key reicht, die Tabellen sind
// für anon beschreibbar). Fehlen sie, werden sie aus config.js gelesen.

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const HALLS = [
  { name: 'PADELZONE WIENERBERG', facilityId: 77636, slug: 'padelzone-wien-or-candc-wienerberg' },
  { name: 'PADELZONE VÖSENDORF',  facilityId: 82615, slug: 'padelzone-voesendorf' },
];
const SPORT = { id: 978, slug: 'padel', name: 'Padel', uuid: 'b388f5e3-69de-11e8-bdc6-02bd505aa7b2' };
const BASE = 'https://www.eversports.at';
const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0 Safari/537.36';
const WEEKS = 5;           // diese Woche + 4 Wochen voraus, wie in der App
const DRY = process.argv.includes('--dry');

// ---------- Supabase ----------
const here = dirname(fileURLToPath(import.meta.url));
function supabaseConfig() {
  let url = process.env.SUPABASE_URL, key = process.env.SUPABASE_KEY;
  if (!url || !key) {
    const cfg = readFileSync(join(here, '..', 'config.js'), 'utf8');
    url = url || (cfg.match(/supabaseUrl:\s*['"]([^'"]+)['"]/) || [])[1];
    key = key || (cfg.match(/supabaseAnonKey:\s*['"]([^'"]+)['"]/) || [])[1];
  }
  if (!url || !key) throw new Error('SUPABASE_URL / SUPABASE_KEY fehlen');
  return { url: url.replace(/\/$/, ''), key };
}
const SB = supabaseConfig();
async function sb(path, init = {}) {
  const r = await fetch(`${SB.url}/rest/v1/${path}`, { ...init, headers: { apikey: SB.key, Authorization: `Bearer ${SB.key}`, 'Content-Type': 'application/json', ...(init.headers || {}) } });
  if (!r.ok) throw new Error(`Supabase ${path}: ${r.status} ${await r.text()}`);
  const t = await r.text(); return t ? JSON.parse(t) : null;
}

// ---------- Eversports ----------
async function fetchCalendar(h, date) {
  const body = new URLSearchParams({ facilityId: String(h.facilityId), facilitySlug: h.slug, 'sport[id]': String(SPORT.id), 'sport[slug]': SPORT.slug, 'sport[name]': SPORT.name, 'sport[uuid]': SPORT.uuid, date, type: 'user' });
  const r = await fetch(`${BASE}/api/booking/calendar/update`, { method: 'POST', body, headers: { 'User-Agent': UA, 'X-Requested-With': 'XMLHttpRequest', Referer: `${BASE}/sb/${h.slug}`, 'Accept-Language': 'de-AT,de;q=0.9' } });
  if (!r.ok) throw new Error(`Kalender ${h.name} ${date}: HTTP ${r.status}`);
  return r.text();
}
async function fetchBooked(h, date, courtIds) {
  const q = new URLSearchParams({ facilityId: String(h.facilityId), startDate: date }); courtIds.forEach(c => q.append('courts[]', String(c)));
  const r = await fetch(`${BASE}/api/slot?${q}`, { headers: { 'User-Agent': UA, 'X-Requested-With': 'XMLHttpRequest', Referer: `${BASE}/sb/${h.slug}`, Accept: 'application/json' } });
  if (!r.ok) throw new Error(`Slots ${h.name} ${date}: HTTP ${r.status}`);
  return (await r.json()).slots || [];
}
const attr = (tag, name) => { const m = tag.match(new RegExp(`${name}=['"]([^'"]*)['"]`)); return m ? m[1] : null; };
const toMin = s => Math.floor(+s / 100) * 60 + (+s % 100);

// Kalender-HTML → Plätze in Reihenfolge der Seite und freie Zeitfenster je Tag und Platz
function parseCalendar(html) {
  const courts = []; const seen = new Set();
  for (const m of html.matchAll(/<td data-court="(\d+)"[^>]*>[\s\S]*?court-name[^>]*>([^<]*)</g)) { if (!seen.has(m[1])) { seen.add(m[1]); courts.push({ id: +m[1], name: m[2].trim() }); } }
  const days = {};   // date → { courtId → [{start,end,state}] }
  for (const tb of html.matchAll(/<tbody data-date="(\d{4}-\d{2}-\d{2})">([\s\S]*?)<\/tbody>/g)) {
    const date = tb[1], cells = {};
    for (const td of tb[2].matchAll(/<td [^>]*data-state="[^"]*"[^>]*>/g)) {
      const t = td[0], court = attr(t, 'data-court'), start = attr(t, 'data-start'), end = attr(t, 'data-end');
      if (!court || !start || !end) continue;
      (cells[court] = cells[court] || []).push({ start: toMin(start), end: toMin(end), state: attr(t, 'data-state') });
    }
    days[date] = cells;
  }
  return { courts, days };
}

// Tag → Raster { stunde: 'oX.' } in der Reihenfolge der Plätze; 'o' frei, 'X' belegt, '.' nicht buchbar
function buildGrid(cells, courts, bookedSet, date) {
  const grid = {}; let anyFree = false;
  for (let hh = 0; hh < 24; hh++) {
    let row = '';
    for (const c of courts) {
      const list = cells[c.id] || []; const h0 = hh * 60, h1 = h0 + 60;
      const covering = list.filter(x => x.start < h1 && x.end > h0);
      if (!covering.length) { row += '.'; continue; }
      let free = true, closed = true;
      for (let m = h0; m < h1; m += 30) {
        const cell = covering.find(x => x.start <= m && x.end > m);
        if (!cell) { free = false; continue; }
        if (cell.state !== 'closed') closed = false;
        if (cell.state !== 'free' || bookedSet.has(`${date}|${c.id}|${cell.start}`)) free = false;
      }
      row += closed ? '.' : free ? 'o' : 'X'; if (free && !closed) anyFree = true;
    }
    if (/^\.+$/.test(row)) continue;   // Stunde ohne buchbaren Platz weglassen
    grid[hh] = row;
  }
  return { grid, anyFree };
}

// ---------- Hauptlauf ----------
const pad = n => String(n).padStart(2, '0');
const iso = d => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
function monday(d) { const x = new Date(d); x.setHours(12, 0, 0, 0); x.setDate(x.getDate() - ((x.getDay() + 6) % 7)); return x; }

async function importHall(h) {
  const dbHall = (await sb(`halls?select=id,name,courts,singles&name=eq.${encodeURIComponent(h.name)}`))[0];
  if (!dbHall) { console.warn(`[${h.name}] nicht in der Datenbank, übersprungen`); return; }
  const groups = (await sb(`group_halls?select=group_id&hall_id=eq.${dbHall.id}`)).map(x => x.group_id);
  if (!groups.length) { console.warn(`[${h.name}] keinem Team zugeordnet, übersprungen`); return; }

  const mon = monday(new Date()), rows = [], stamp = new Date().toISOString(); let courts = null, first = 24, last = 0, nDays = 0, nFree = 0;
  for (let w = 0; w < WEEKS; w++) {
    const d = new Date(mon); d.setDate(d.getDate() + w * 7); const date = iso(d);
    const cal = parseCalendar(await fetchCalendar(h, date));
    if (!cal.courts.length) { console.warn(`[${h.name}] ${date}: keine Plätze im Kalender`); continue; }
    courts = courts || cal.courts;
    if (cal.courts.length !== dbHall.courts) console.warn(`[${h.name}] Eversports zeigt ${cal.courts.length} Plätze, App hat ${dbHall.courts}: ${cal.courts.map(c => c.name).join(', ')}`);
    const booked = await fetchBooked(h, date, cal.courts.map(c => c.id));
    const bookedSet = new Set(booked.map(s => `${s.date}|${s.court}|${toMin(s.start)}`));
    for (const [day, cells] of Object.entries(cal.days)) {
      const { grid, anyFree } = buildGrid(cells, cal.courts, bookedSet, day);
      const hours = Object.keys(grid).map(Number);
      if (!hours.length) continue;                       // Tag noch nicht buchbar: nichts schreiben
      first = Math.min(first, ...hours); last = Math.max(last, ...hours);
      nDays++; nFree += Object.values(grid).join('').split('o').length - 1;
      for (const group_id of groups) rows.push({ group_id, hall_id: dbHall.id, date: day, court: dbHall.name, grid, source: 'eversports', imported_at: stamp });
      if (DRY) console.log(`${h.name} ${day}  ` + hours.map(hh => `${pad(hh)}:${grid[hh]}`).join(' '));
    }
  }
  console.log(`[${h.name}] ${nDays} Tage, ${nFree} freie Platz-Stunden, Plätze: ${(courts || []).map(c => c.name).join(' | ')}`);
  if (DRY || !rows.length) return;
  for (let i = 0; i < rows.length; i += 200) await sb('court_grid?on_conflict=group_id,hall_id,date', { method: 'POST', headers: { Prefer: 'resolution=merge-duplicates,return=minimal' }, body: JSON.stringify(rows.slice(i, i + 200)) });
  if (first <= last) await sb(`halls?id=eq.${dbHall.id}`, { method: 'PATCH', headers: { Prefer: 'return=minimal' }, body: JSON.stringify({ first_hour: first, last_hour: last }) });
  console.log(`[${h.name}] ${rows.length} Zeilen für ${groups.length} Team(s) geschrieben`);
}

let failed = false;
for (const h of HALLS) {
  try { await importHall(h); } catch (e) { failed = true; console.error(`[${h.name}] FEHLER: ${e.message}`); }
}
process.exit(failed ? 1 : 0);
