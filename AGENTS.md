# AGENTS.md — Reshima (רשימה) Agent Operating Guide

This repository is designed to be **100% managed by AI Coding Agents (Google Gemini / Antigravity)** and automated via **GitHub Actions CI/CD**.

## 1. Architecture Overview
- **iOS App (`ios/`)**: Native SwiftUI (iOS 17+) managed declaratively via **XcodeGen** (`ios/project.yml`). Never commit `.xcodeproj` files; always edit Swift source files and `ios/project.yml`.
- **Shared Core & Local CLI Tests (`Package.swift`)**: Compiles `ios/Reshima/Models` (domain models, aisle sorting, localization, autocomplete, and the sync merge/outbox logic in `SyncEngine.swift`) as a plain Swift package. `swift build` works with Command Line Tools only; `swift test` needs full Xcode (XCTest) and always runs in CI.
- **Backend (`supabase/`)**: PostgreSQL migrations (`supabase/migrations/*.sql`), Row-Level Security (RLS), Realtime change events, and the private `item-photos` Storage bucket.
- **Access model**: each phone signs in anonymously (Supabase Auth) and calls `join_household(invite_code)`. Every table and Storage policy requires `is_household_member(...)`. The repo, the IPA and the anon key are public, so nothing secret may be committed or built into the app.
- **CI/CD (`.github/workflows/`)**:
  - `supabase-deploy.yml`: Applies new SQL migrations on merge to `main` and records them in `supabase_migrations.schema_migrations` (the Supabase CLI's own history table, so `make db-push` stays compatible).
  - `supabase-keepalive.yml`: Runs a scheduled query twice a week so the Supabase Free Tier never pauses.
  - `ios-ci-release.yml`: Generates the Xcode project on GitHub's macOS runner, runs tests, builds `Reshima.ipa`, and updates the **SideStore / AltStore** OTA feed (`altstore-source.json`) so both iPhones receive updates over Wi-Fi using a free Apple ID.

## 2. Key Commands for Agents

```bash
# Run unit tests locally (requires full Xcode; with Command Line Tools only, use `swift build` and rely on CI for tests)
make test

# Generate Reshima.xcodeproj from ios/project.yml (requires XcodeGen)
make generate

# Validate SQL migrations syntax
make check-sql

# Install developer CLI tools (xcodegen, swiftlint, supabase, gh)
make setup

# Push database migrations to Supabase (or let GitHub Actions do it on push to main)
make db-push
```

## 3. Coding Conventions & Rules for Agents
1. **Adding/Removing iOS Files**: Simply create or delete `.swift` files inside `ios/Reshima/`. Because `ios/project.yml` includes the directory tree `ios/Reshima`, XcodeGen automatically discovers new Swift files without needing manual project edits.
2. **Database Changes**: Never modify existing migration files once merged to `main`. Always create a new timestamped migration in `supabase/migrations/YYYYMMDDHHMMSS_description.sql` (lowercase, digits and underscores only) and write it so it is safe to re-run (`if exists` / `create or replace`).
   - Never add a policy with `using (true)` or grant access to `anon`. New tables need RLS enabled plus an `is_household_member(household_id)` policy.
   - `security definer` functions must `set search_path = ''`, check `auth.uid()`, and have `execute` revoked from roles that should not call them.
3. **Bilingual (Hebrew RTL & English LTR) Support**:
   - Every user-facing string must have both Hebrew (`he`) and English (`en`) translations in `L10n` (`ios/Reshima/Models/AppLanguage.swift`).
   - Respect layout direction (`layoutDirection`) and avoid hardcoded `.leading`/`.trailing` overrides.
4. **Optimistic Real-Time UI**:
   - All list interactions (checking off an item, changing quantity, adding an item) must update the local `@Observable` state immediately (`<16ms`) before awaiting the Supabase network response.
5. **Sync Rules (`ShoppingStore` + `SyncEngine.swift`)**:
   - A user action = update local state, record it in the outbox (`PendingItemQueue` / `pendingCatalog` / `pendingCategoryOrder`), call `commitLocalChange()`. Never call Supabase directly from an action.
   - Item edits are sent as partial updates (`ItemPatch`, only changed fields). Never upsert a whole row for an edit: it overwrites the other phone's changes.
   - Server data is applied only through `SyncMerge` (server wins unless a local change is pending). Never assign fetched rows straight to `items`.
   - Built-in aisles are identified by `Category.kind`, never by `sortOrder` (users reorder aisles).
   - Photos live in Storage at `<household_id>/<file>.jpg`; `photo_path` holds that object path, never a local file path.
   - Sync logic that can be expressed without Supabase belongs in `ios/Reshima/Models` with tests in `ios/ReshimaTests/SyncLogicTests.swift`.
