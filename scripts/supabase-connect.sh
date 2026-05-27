#!/usr/bin/env bash
# Authenticate Supabase CLI (browser) and link this repo to the remote project.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_REF="${SUPABASE_PROJECT_REF:-tndzkbvpbssnojyxjqpj}"
PROJECT_URL="https://${PROJECT_REF}.supabase.co"

cd "$ROOT"

echo "→ Project: Kept Dev"
echo "  URL:     $PROJECT_URL"
echo "  Ref:     $PROJECT_REF"
echo

if [[ ! -f supabase/config.toml ]]; then
  echo "→ Initializing Supabase config..."
  supabase init
fi

echo "→ Opening browser to sign in to Supabase..."
echo "  (Complete login in the browser, then return here.)"
supabase login

echo
echo "→ Linking local folder to remote project..."
if [[ -n "${SUPABASE_DB_PASSWORD:-}" ]]; then
  supabase link --project-ref "$PROJECT_REF" --password "$SUPABASE_DB_PASSWORD" --yes
else
  echo "  You may be prompted for your database password (Dashboard → Project Settings → Database)."
  supabase link --project-ref "$PROJECT_REF" --yes
fi

echo
echo "✓ Connected. Useful commands (run from $ROOT):"
echo "  supabase migration list          # compare local vs remote migrations"
echo "  supabase db push --dry-run       # preview migrations to apply"
echo "  supabase db push                 # apply migrations to $PROJECT_URL"
echo "  supabase functions deploy        # deploy edge functions"
echo "  supabase projects list           # list projects in your account"
