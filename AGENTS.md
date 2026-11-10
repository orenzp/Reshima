# AGENTS.md — Reshima (רשימה) Agent Operating Guide

This repository is designed to be **100% managed by AI Coding Agents (Google Gemini / Antigravity)** and automated via **GitHub Actions CI/CD**.

## 1. Architecture Overview
- **iOS App (`ios/`)**: Native SwiftUI (iOS 17+) managed declaratively via **XcodeGen** (`ios/project.yml`). Never commit `.xcodeproj` files; always edit Swift source files and `ios/project.yml`.
- **Shared Core & Local CLI Tests (`Package.swift`)**: Allows agents to compile and unit-test domain models, aisle sorting, Hebrew/English localization, and smart autocomplete locally using `swift test` (even on Macs with only Command Line Tools installed).
- **Backend (`supabase/`)**: Declarative PostgreSQL migrations (`supabase/migrations/*.sql`), Row-Level Security (RLS), Realtime WebSocket sync, and `item-photos` Storage bucket.
- **CI/CD (`.github/workflows/`)**:
  - `supabase-deploy.yml`: Automatically pushes new SQL migrations to Supabase on merge to `main`.
  - `supabase-keepalive.yml`: Runs a scheduled query twice a week so the Supabase Free Tier never pauses.
  - `ios-ci-release.yml`: Generates the Xcode project on GitHub's macOS runner, runs tests, builds `Reshima.ipa`, and updates the **SideStore / AltStore** OTA feed (`altstore-source.json`) so both iPhones receive updates over Wi-Fi using a free Apple ID.

## 2. Key Commands for Agents

```bash
# Run unit tests locally (works with Swift Command Line Tools, no full Xcode needed)
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
2. **Database Changes**: Never modify existing migration files once merged to `main`. Always create a new timestamped migration in `supabase/migrations/YYYYMMDDHHMMSS_description.sql`.
3. **Bilingual (Hebrew RTL & English LTR) Support**:
   - Every user-facing string must have both Hebrew (`he`) and English (`en`) translations in `L10n.swift`.
   - Respect layout direction (`layoutDirection`) and avoid hardcoded `.leading`/`.trailing` overrides.
4. **Optimistic Real-Time UI**:
   - All list interactions (checking off an item, changing quantity, adding an item) must update the local `@Observable` state immediately (`<16ms`) before awaiting the Supabase network response.
