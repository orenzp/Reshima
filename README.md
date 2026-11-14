# Reshima (רשימה) 🛒

A collaborative, real-time iOS shopping list application for you and your wife, built with **Native SwiftUI (iOS 17+)** and **Supabase**, designed to be **100% managed by AI Coding Agents (Google Gemini)** and **GitHub Actions CI/CD**.

---

## ✨ Features (Phase 1 MVP)
- **Real-Time Shared Shopping List**: Instant check-off (`<16ms` optimistic UI + Supabase sync) with a collapsible *"In Cart / בסל"* drawer.
- **Supermarket Aisle Sorting**: Automatically groups items by supermarket department (*Produce / פירות וירקות, Dairy & Eggs / מוצרי חלב וביצים, Bakery / מאפים ולחם, Meat & Fish / בשר ודגים*, etc.) with drag-and-drop aisle reordering.
- **Full Bilingual Support (Hebrew RTL & English LTR)**: Instant toggle between `עברית` and `English`, including localized units (`יח׳`, `ק״ג`, `גרם`, `ליטר`, `חב׳` / `pcs`, `kg`, `g`, `L`, `pack`).
- **Smart Autocomplete & Staples Bar**: Remembers your past items, ranks suggestions by usage frequency, and auto-detects the right aisle and unit in both Hebrew and English.
- **Quantities, Units, Notes & Photos**: Inline `+ / -` steppers on every row, plus item detail sheets for brand notes and photos.
- **Offline-First Resilience**: Caches everything locally and queues your changes, so the app works inside supermarkets with poor reception and catches up when the signal returns.
- **Private by Default**: Each phone signs in anonymously and joins your household with a long random invite code; Row-Level Security blocks everyone else, even though the repo and the app's API key are public.

---

## 🚀 5-Minute Cloud & GitHub Actions Setup

### Step 1: Create Your Free Supabase Project
1. Go to [supabase.com](https://supabase.com/) and create a new free project named `Reshima`.
2. Copy the following values from your Supabase dashboard:
   - **Project URL** (`Settings -> API -> Project URL`)
   - **Anon Public Key** (`Settings -> API -> Project API keys -> anon public`)
   - **Project Reference ID** (`Settings -> General -> Reference ID`)
   - **Database Password** (the password you chose when creating the project)
   - **Personal Access Token** ([supabase.com/dashboard/account/tokens](https://supabase.com/dashboard/account/tokens))

### Step 2: Push to GitHub & Add Repository Secrets
1. Create a new repository on your GitHub account (e.g. `Reshima`) and push this repo:
   ```bash
   git remote add origin git@github.com:<your-username>/Reshima.git
   git push -u origin main
   ```
2. In your GitHub repo, go to **Settings -> Secrets and variables -> Actions** and add these 4 Repository Secrets:
   - `SUPABASE_URL`
   - `SUPABASE_ANON_KEY`
   - `SUPABASE_PROJECT_REF`
   - `SUPABASE_ACCESS_TOKEN`
3. Once added, GitHub Actions will automatically:
   - Apply every file in `supabase/migrations/` (tables, RLS policies, Realtime, Storage bucket) and enable anonymous sign-ins (`supabase-deploy.yml`).
   - Ping your database every Monday and Thursday so the Supabase Free Tier never pauses (`supabase-keepalive.yml`).
   - Build `Reshima.ipa` and publish a GitHub Release (`ios-ci-release.yml`).

### Step 3: Install on Your & Your Wife's iPhones (Free Apple ID)
Because you are using a free Apple ID:
- **Option A — Over-The-Air via SideStore (Recommended)**:
  1. Install [SideStore](https://sidestore.io/) once on both iPhones.
  2. Download `Reshima.ipa` from your GitHub repo's **Releases** tab (or add the generated `altstore-source.json` URL to SideStore Sources).
  3. SideStore will automatically refresh the 7-day free Apple ID signature in the background over Wi-Fi without needing a computer!
- **Option B — Direct Wireless Install from Mac**:
  ```bash
  make deploy-iphones
  ```

### Step 4: Connect Both Phones to Your Household
The household invite code is generated inside your database and is never stored in this repo or in the app.
1. In the Supabase dashboard open **SQL Editor** and run:
   ```sql
   select name, invite_code from public.households;
   ```
2. On each iPhone open Reshima -> **Settings** (slider icon), type the code under *Shared Household Code* and tap **Save & Connect**.
3. The badge at the top turns green (*Live Sync Active*). Until a code is entered the list stays on that phone only.

Treat the code like a password: anyone who has it can join your list. To replace it, run
`update public.households set invite_code = upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 20));` and re-enter it on both phones.

---

## 🤖 Managing Reshima via Gemini Agents
See [AGENTS.md](./AGENTS.md) for the complete guide used by AI agents. Common commands:
- `make test` — Run Swift unit tests locally (`swift test`).
- `make generate` — Generate `ios/Reshima.xcodeproj` from `ios/project.yml`.
- `make db-push` — Push new SQL migrations to Supabase.
