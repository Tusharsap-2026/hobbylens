# HobbyLens

A bilingual (Bangla and English) Android app for plant lovers and owners of cats, dogs and birds.
Take a photo, find out what it is, get care basics, see where to buy what you need nearby, and keep
your plants and pets in My Collection with care reminders.

"HobbyLens" is a working name.

## What is in this repository

| Folder | What it is | Tested here |
| --- | --- | --- |
| `app/` | Flutter app (Android first, iOS-ready) | Static checks and tests written; compiled and run in CI (see below) |
| `supabase/migrations/` | PostgreSQL + PostGIS schema, security rules, starter content | 58 pgTAP tests |
| `supabase/functions/` | Edge functions: identification gateway, AI care tips, account deletion, cleanup, SMS hook | 30 unit tests + PostgREST integration test |
| `tools/bakeoff/` | Week-1 engine bake-off on local photos | 10 unit tests |
| `tools/db/` | Database and integration test runners | – |
| `docs/` | Setup, accounts and release guide; build status | – |

## How it fits together

```
Phone (Flutter)                         Supabase (Singapore/Mumbai)                 Outside services
───────────────                         ───────────────────────────                 ────────────────
photo, resized to 1024 px ─────────────▶ identify function ──────────────────────▶ Plant.id / Pl@ntNet (plants)
on-device ML Kit label (free) ─ hint ──▶   quota, routing, 60% rule,               Gemini / Claude (pets, routing)
                                           Bangla names, care cards, photo kept 24 h
shop search (lat, lng, radius) ────────▶ nearby_shops() in PostGIS (our own shop directory)
My Collection + reminders (SQLite) ◀──▶ collection_items, reminders (row-level security)
phone number at first save ────────────▶ Supabase Auth ── send-sms hook ─────────▶ Bangladeshi SMS gateway
```

Key decisions, from the build plan:

- **Guest first.** Every install signs in anonymously; the phone number is verified only at the first
  "Save to My Collection". The database refuses saves from guests.
- **No keys in the app.** Engines are called only from the `identify` function.
- **Never present a guess as certain.** Below 60% the app shows "We're not sure" with the guesses
  clearly marked. Animals show High, Medium or Low rather than a percentage.
- **Our own shop directory.** Google's terms allow storing only place IDs, so shops come from a field
  survey. Partner stock (Phase 2) shows a badge for 14 days after each confirmation.
- **Live animals are not sold through the app.** Animals get supplies, pet shops and vets.
- **Offline.** My Collection and reminders live in SQLite on the phone and sync when online.
- **Privacy.** Unsaved photos are deleted after 24 hours; location is never stored; account
  deletion removes every row and photo.

## Quick start

See [docs/SETUP.md](docs/SETUP.md) for the full guide. In short:

```bash
# Backend tests (needs PostgreSQL 16 + PostGIS + pgTAP, Deno, PostgREST)
PGHOST=localhost PGPORT=5432 tools/db/test.sh
(cd supabase/functions && deno test --allow-env tests/)
PGHOST=localhost PGPORT=5432 tools/db/integration.sh

# App
cd app
tool/bootstrap_platforms.sh          # once: generates Gradle wrapper and iOS project
flutter pub get
flutter test
flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_PUBLISHABLE_KEY=...
```

Current status and what comes next: [docs/STATUS.md](docs/STATUS.md).

## Clickable preview

`docs/preview/hobbylens-preview.html` is a browser preview of the app's screens in Bangla and English, using the
same text and demo data (fictional shops near GEC Circle, Chattogram). Open it in any browser to walk through
the flow. It is for showing the design, not a substitute for the real app.
