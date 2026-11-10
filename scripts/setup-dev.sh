#!/usr/bin/env bash
set -euo pipefail

echo "==> Checking Homebrew installation..."
if ! command -v brew >/dev/null 2>&1; then
  echo "Error: Homebrew is required. Install from https://brew.sh"
  exit 1
fi

TOOLS=(xcodegen swiftlint gh)
for tool in "${TOOLS[@]}"; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "==> Installing $tool..."
    brew install "$tool"
  else
    echo "==> $tool is already installed."
  fi
done

if ! command -v supabase >/dev/null 2>&1; then
  echo "==> Installing Supabase CLI..."
  brew install supabase/tap/supabase
else
  echo "==> supabase CLI is already installed."
fi

echo "==> Development environment setup complete!"
