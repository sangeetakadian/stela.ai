#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${CODE_EXEC_ENDPOINT:-}" ]]; then
  echo "Set CODE_EXEC_ENDPOINT for this Vercel environment." >&2
  exit 1
fi

if [[ "${ISTELA_ASSESSMENT_PILOT_BUILD:-}" != "true" ]]; then
  flutter build web --release \
    --dart-define=CODE_EXEC_ENDPOINT="$CODE_EXEC_ENDPOINT"
  exit
fi

if [[ "${VERCEL_ENV:-}" != "preview" ]]; then
  echo "Assessment pilot builds are only allowed in the Vercel Preview environment." >&2
  exit 1
fi

required_pilot_variables=(
  PILOT_FIREBASE_API_KEY
  PILOT_FIREBASE_APP_ID
  PILOT_FIREBASE_MESSAGING_SENDER_ID
  PILOT_FIREBASE_PROJECT_ID
  PILOT_FIREBASE_DATABASE_URL
  PILOT_FIREBASE_AUTH_DOMAIN
  PILOT_FIREBASE_STORAGE_BUCKET
)

for key in "${required_pilot_variables[@]}"; do
  if [[ -z "${!key:-}" ]]; then
    echo "Missing Preview environment variable: $key" >&2
    exit 1
  fi
done

if [[ "$PILOT_FIREBASE_PROJECT_ID" == "stela23-f9a52" ]]; then
  echo "Pilot Preview cannot target the existing shared Firebase project." >&2
  exit 1
fi

flutter build web --release \
  --dart-define=ISTELA_ASSESSMENT_PILOT=true \
  --dart-define=PILOT_FIREBASE_API_KEY="$PILOT_FIREBASE_API_KEY" \
  --dart-define=PILOT_FIREBASE_APP_ID="$PILOT_FIREBASE_APP_ID" \
  --dart-define=PILOT_FIREBASE_MESSAGING_SENDER_ID="$PILOT_FIREBASE_MESSAGING_SENDER_ID" \
  --dart-define=PILOT_FIREBASE_PROJECT_ID="$PILOT_FIREBASE_PROJECT_ID" \
  --dart-define=PILOT_FIREBASE_DATABASE_URL="$PILOT_FIREBASE_DATABASE_URL" \
  --dart-define=PILOT_FIREBASE_AUTH_DOMAIN="$PILOT_FIREBASE_AUTH_DOMAIN" \
  --dart-define=PILOT_FIREBASE_STORAGE_BUCKET="$PILOT_FIREBASE_STORAGE_BUCKET" \
  --dart-define=PILOT_FIREBASE_MEASUREMENT_ID="${PILOT_FIREBASE_MEASUREMENT_ID:-}" \
  --dart-define=CODE_EXEC_ENDPOINT="$CODE_EXEC_ENDPOINT"
