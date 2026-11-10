# Reshima (רשימה) 🛒

A collaborative, real-time iOS shopping list application for you and your wife, built with **Native SwiftUI (iOS 17+)** and **Supabase**, designed to be **100% managed by AI Coding Agents (Google Gemini)** and **GitHub Actions CI/CD**.

---

## ✨ Features (Phase 1 MVP)
- **Real-Time Shared Shopping List**: Instant check-off (`<16ms` optimistic UI + Supabase sync) with a collapsible *"In Cart / בסל"* drawer.
- **Supermarket Aisle Sorting**: Automatically groups items by supermarket department (*Produce / פירות וירקות, Dairy & Eggs / מוצרי חלב וביצים, Bakery / מאפים ולחם, Meat & Fish / בשר ודגים*, etc.) with drag-and-drop aisle reordering.
- **Full Bilingual Support (Hebrew RTL & English LTR)**: Instant toggle between `עברית` and `English`, including localized units (`יח׳`, `ק״ג`, `גרם`, `ליטר`, `חב׳` / `pcs`, `kg`, `g`, `L`, `pack`).
- **Smart Autocomplete & Staples Bar**: Remembers your past items, ranks suggestions by usage frequency, and auto-detects the right aisle and unit in both Hebrew and English.
- **Quantities, Units, Notes & Photos**: Inline `+ / -` steppers on every row, plus item detail sheets for brand notes and photos.
- **Offline-First Resilience**: Caches everything locally on your iPhone so the app works smoothly even inside supermarkets with poor reception.

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
2. In your GitHub repo, go to **Settings -> Secrets and variables -> Actions** and add these 5 Repository Secrets:
   - `SUPABASE_URL`
   - `SUPABASE_ANON_KEY`
   - `SUPABASE_PROJECT_REF`
   - `SUPABASE_DB_PASSWORD`
   - `SUPABASE_ACCESS_TOKEN`
3. Once added, GitHub Actions will automatically:
   - Apply `supabase/migrations/20261109000000_init.sql` to create your tables, RLS policies, Realtime channels, and Storage bucket (`supabase-deploy.yml`).
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

---

## 🤖 Managing Reshima via Gemini Agents
See [AGENTS.md](./AGENTS.md) for the complete guide used by AI agents. Common commands:
- `make test` — Run Swift unit tests locally (`swift test`).
- `make generate` — Generate `ios/Reshima.xcodeproj` from `ios/project.yml`.
- `make db-push` — Push new SQL migrations to Supabase.
