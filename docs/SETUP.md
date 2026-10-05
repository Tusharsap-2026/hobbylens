# Setup, accounts and release

## 1. Accounts to open in your company's name (week 1)

Every account below should belong to the company that owns HobbyLens, with you as owner and the
developers added as members. Keys are then handed over simply by removing the developers' access.

| Account | Used for | Cost | Notes |
| --- | --- | --- | --- |
| GitHub organisation | Source code, CI, APK builds | Free | Private repository |
| Supabase | Database, auth, storage, edge functions | Pro plan USD 25/month | Region Singapore (ap-southeast-1) or Mumbai (ap-south-1) |
| Kindwise (Plant.id) | Plant identification | Pay per credit, from EUR 50 | Needed for the bake-off |
| Pl@ntNet | Plant identification (challenger) | Free up to 500/day | Bake-off |
| Google AI Studio (Gemini) or Anthropic | Pets, birds, routing, AI care tips | Pay per token | Pick one after the bake-off |
| Bangladeshi SMS gateway (BTRC-licensed) | Phone OTP | About BDT 0.35/SMS | Ask for its HTTP API document |
| Google Play Console (organisation account) | Publishing | USD 25 once | An organisation account (needs a D-U-N-S number) avoids the 12-tester, 14-day rule for new personal accounts |
| Firebase (later, week 10) | Crash reporting (Crashlytics) | Free | For the 99% crash-free target |

## 2. Supabase project

1. Create the project, then link it locally: `supabase link --project-ref <ref>`.
2. Apply the schema and starter content: `supabase db push` (runs `supabase/migrations/` in order).
   `supabase/seed.sql` holds fictional demo shops and is for local development only.
3. **Authentication**
   - Enable anonymous sign-ins (Authentication > Providers > Anonymous).
   - Turn on CAPTCHA (Turnstile or hCaptcha) for sign-ins to limit mass guest creation.
   - Enable the Phone provider. Under Authentication > Hooks, add a **Send SMS hook** of type
     HTTPS pointing to `https://<ref>.supabase.co/functions/v1/send-sms`, and copy its secret.
4. **Function secrets**: copy `supabase/functions/.env.example`, fill it in, then
   `supabase secrets set --env-file supabase/functions/.env`. Deploy with
   `supabase functions deploy identify care-tips delete-account cleanup send-sms`.
   `send-sms` and `cleanup` are deployed with JWT verification off (see `supabase/config.toml`).
5. **Scheduled cleanup**: create a Supabase cron job (Integrations > Cron) that calls the `cleanup`
   function hourly with header `Authorization: Bearer <CLEANUP_SECRET>`. It deletes unsaved photos
   after 24 hours and guest accounts unused for 30 days.
6. **Admins**: add a staff member's user id to `public.app_admins` to let them edit taxa, care cards,
   shops and the catalogue, and triage "Not right?" reports. The admin panel itself is a later step
   (see STATUS.md); until then use the Supabase table editor.

### SMS gateway settings

Bangladeshi gateways differ, so the `send-sms` function uses a URL template. From the gateway's API
document, set `SMS_URL_TEMPLATE` (with `{api_key}`, `{sender_id}`, `{to}`, `{message}`),
`SMS_HTTP_METHOD`, `SMS_NUMBER_FORMAT` (`880`, `e164` or `local`) and `SMS_SUCCESS_PATTERN`
(a regular expression matching the gateway's success reply). With `SMS_PROVIDER=console` the codes
are only written to the function log, which is useful for local testing.

## 3. The app

```bash
cd app
tool/bootstrap_platforms.sh   # generates the Gradle wrapper, iOS project and launcher icons
flutter pub get
flutter test
flutter run \
  --dart-define=SUPABASE_URL=https://<ref>.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=<publishable key>
```

- The publishable key is safe to ship: it only identifies the project; row-level security protects
  the data. The service-role key must never be in the app.
- UI text lives in `tool/strings.py` (Bangla and English side by side). Run
  `python3 tool/strings.py` to regenerate the ARB files, and `python3 tool/check_l10n.py` to check
  that nothing is hard-coded and both languages match.
- The Android application id is `com.hobbylens.hobbylens`. It cannot change after the first Play
  upload, so confirm the final name first (`app/android/app/build.gradle.kts`).

### Signing and release

1. Create an upload key (`keytool -genkey -v -keystore upload.jks -alias upload ...`) and keep it
   in the company password manager. Replace the debug signing in `android/app/build.gradle.kts`
   with a release signing config that reads `android/key.properties` (not committed).
2. `flutter build appbundle --release --dart-define=...` and upload the `.aab` to Play Console.
3. Closed test with at least 12 testers for 14 days (mandatory for new personal accounts; good
   practice anyway), then production.

## 4. Running the tests locally

| What | Command | Needs |
| --- | --- | --- |
| Database (pgTAP) | `PGHOST=... PGPORT=... tools/db/test.sh` | PostgreSQL 16, PostGIS 3, pgTAP |
| Functions | `cd supabase/functions && deno test --allow-env tests/` | Deno 2 |
| Functions + database | `tools/db/integration.sh` | the above + PostgREST 13 |
| Refresh app fixtures | `MAKE_FIXTURES=1 tools/db/integration.sh` | same |
| App | `cd app && flutter test` | Flutter 3.47 |
| Bake-off tool | `cd tools/bakeoff && python3 -m unittest test_bakeoff` | Python 3.10+ |

The app's contract tests read `app/test/fixtures/`, which are produced by running the real gateway
code against the real database. If the API changes, refresh the fixtures and the app tests will show
what broke.

## 5. The week-1 engine bake-off

```bash
cd tools/bakeoff
pip install -r requirements.txt
export PLANTID_API_KEY=... PLANTNET_API_KEY=... GEMINI_API_KEY=...
python3 bakeoff.py --photos photos/ --labels labels.csv --engines plantid,plantnet,gemini
```

`labels.example.csv` shows the label format. Aim for 300 photos (200 plants across about 20
species, 100 pets), labelled by a nursery owner or horticulturist. The tool writes `results/report.md`
with the recommended engine under the plan's rule: cheapest engine with at least 85% top-3 species
accuracy and a 90th-percentile response time of 4 seconds or less. Set `PLANT_ENGINE` in the
function secrets to the winner.
