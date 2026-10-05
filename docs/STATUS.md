# Build status

Status as of 5 October 2026, against the Phase 1 plan (12 weeks).

## Done

| Area | What exists | Evidence |
| --- | --- | --- |
| Database | 20 tables, PostGIS shop search, opening hours in Dhaka time, partner-stock ranking, accessory lookup, taxon matching with genus fallback, quotas, analytics view for the admin dashboard, row-level security, private photo storage | 58 pgTAP tests pass |
| Starter content | 18 species and breeds with Bangla names, draft care cards, 19 categories, 25 catalogue items | Loaded by migration; **care cards are drafts awaiting expert review**; **prices are blank until the shop survey** |
| Identification gateway | Plant.id, Pl@ntNet, Gemini and Claude adapters; mock engine; 60% rule; vet advice; 24-hour photo retention; cost tracking | 30 unit tests, PostgREST integration test |
| Other functions | AI care tips (cached), account deletion, hourly cleanup, Send SMS hook for a Bangladeshi gateway | Unit tests for SMS and webhook signatures |
| App | All 14 MVP screens in Bangla and English; guest-first sign-in with phone OTP at first save; on-device photo check; shop search with Call, WhatsApp and Directions; accessories; offline My Collection with reminders and sync; account deletion | 182 strings checked in both languages; contract tests against real server output; widget tests at 360 dp width |
| Bake-off tool | Accuracy at species and genus level with confidence intervals, latency, cost, Bangla-name rate, decision rule | 10 unit tests |
| CI | Database, functions, integration, app analyse/test/APK build, bake-off tool | `.github/workflows/ci.yml` |

## Not yet verified

- **The Flutter app has not been compiled yet.** The workspace it was written in could not reach
  the Flutter SDK or pub.dev. Every package API was checked against that package's source, an
  independent review found no compile errors, and every file parses. The first CI run in GitHub
  is the real test; expect small fixes.
- **No real engine calls yet.** The Plant.id request format follows Kindwise's public examples;
  confirm it during the bake-off. Plant.id's Bangla common-name support is unknown.
- **SMS gateway**: the hook is generic; it needs the chosen gateway's URL template and success reply.

## Next, in plan order

1. Push to the company GitHub repository and get CI green (compiles the app for the first time).
2. Open the accounts in SETUP.md; run the bake-off on 300 local photos.
3. Field survey of Chattogram shops; fill shop data, categories and catalogue prices.
4. Expert review of care cards (horticulturist and vet) for the top 150 species and breeds.
5. Admin panel (weeks 7–9): taxa and care cards, catalogue, shops, flagged results, analytics.
6. Firebase Crashlytics, performance work on 3 GB phones, release signing, closed beta.

## Open decisions

- Live animals stay out of "where to buy" (built this way; confirm after legal advice).
- Final app name and Android application id (currently `com.hobbylens.hobbylens`).
- Legal check on data-localisation duties under the Personal Data Protection Ordinance 2025 before
  choosing the Supabase region.
