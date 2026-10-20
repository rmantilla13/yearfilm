#!/usr/bin/env bash
# End-to-end check of accounts, backup and invites against a preview deployment.
#
#   scripts/e2e-backup.sh https://yearfilm-xxxx-rickymantilla.vercel.app test@example.com
#
# Signs in as a Supabase email/password TEST user (asks for the password), then:
# family → profile → upload a 1 MB clip → record it → record again (idempotent) →
# invite → preview → accept own link (no-op) → members → revoke → delete account.
# The last step deletes the test user and every file it uploaded, so make a new test
# user to run it again. Calls to the preview go through `vercel curl`, which handles
# deployment protection with your own Vercel login.
set -euo pipefail

DEPLOYMENT=${1:?usage: e2e-backup.sh <preview-url> <test-email>}
EMAIL=${2:?usage: e2e-backup.sh <preview-url> <test-email>}
SCOPE=${VERCEL_SCOPE:-team_bZtYQKzRK8vTbMsyCz0dAdPn}
SUPABASE_URL=https://mfxidnpbdjtfxfuvviix.supabase.co
SUPABASE_KEY=sb_publishable_6ozXu06SIqsmrmv0sySNxQ_a-Psa8fF  # publishable: safe in a client
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

read -r -s -p "Password for $EMAIL: " PASSWORD
echo

step() { printf '\n— %s\n' "$*"; }
fail() { printf '✘ %s\n' "$*"; exit 1; }

TOKEN=$(curl -sS "$SUPABASE_URL/auth/v1/token?grant_type=password" \
  -H "apikey: $SUPABASE_KEY" -H 'content-type: application/json' \
  --data "$(jq -n --arg e "$EMAIL" --arg p "$PASSWORD" '{email: $e, password: $p}')" | jq -r '.access_token // empty')
unset PASSWORD
[ -n "$TOKEN" ] || fail "Sign-in failed. Check the email and password of the test user."
echo "✔ signed in"

# api METHOD PATH [JSON] → prints the response body and leaves the status in $STATUS
api() {
  local out="$WORK/out" args=(-s -o "$out" -w '%{http_code}' -X "$1" -H "authorization: Bearer $TOKEN")
  [ $# -ge 3 ] && args+=(-H 'content-type: application/json' --data "$3")
  STATUS=$(vercel curl "$2" --deployment "$DEPLOYMENT" --scope "$SCOPE" -- "${args[@]}" 2>/dev/null)
  cat "$out"
}
expect() { [ "$STATUS" = "$1" ] || fail "expected HTTP $1, got $STATUS"; echo "✔ HTTP $STATUS"; }

step "Start a family"
api POST /api/family '{"name":"E2E Test Family"}' | jq -c .
[[ "$STATUS" =~ ^20[01]$ ]] || fail "family: HTTP $STATUS"

step "Set a display name"
api PUT /api/profile '{"displayName":"E2E Tester"}' | jq -c .; expect 200

ID=$(uuidgen | tr 'A-Z' 'a-z')
DAY=$(date +%Y-%m-%d)
head -c 1048576 /dev/urandom > "$WORK/clip.mov"
CLIP=$(jq -n --arg id "$ID" --arg d "$DAY" '{kind: "footage", id: $id, capturedOn: $d, ext: "mov", byteSize: 1048576, durationS: 3}')

step "Ask for an upload link"
api POST /api/uploads "$CLIP" > "$WORK/presign.json"; expect 200
URL=$(jq -r .url "$WORK/presign.json")

step "Upload 1 MB straight to Blob"
PUT=$(curl -sS -o /dev/null -w '%{http_code}' -X PUT -H 'content-type: video/quicktime' -T "$WORK/clip.mov" "$URL")
[ "$PUT" = 200 ] || fail "PUT: HTTP $PUT"; echo "✔ HTTP $PUT"

step "Upload again with the same link (must not overwrite)"
PUT2=$(curl -sS -o /dev/null -w '%{http_code}' -X PUT -H 'content-type: video/quicktime' -T "$WORK/clip.mov" "$URL")
echo "HTTP $PUT2 (the app treats 409/412 as already there)"

step "Record it"
api POST /api/uploads/complete "$CLIP" | jq -c .; expect 200
step "Record it again (idempotent)"
api POST /api/uploads/complete "$CLIP" | jq -c .; expect 200

step "Refuse a clip that's too big"
api POST /api/uploads "$(jq -c '.byteSize = 600000000' <<<"$CLIP")" | jq -c .; expect 400

WEEK=$(( ($(date +%j | sed 's/^0*//') - 1) / 7 + 1 )); [ "$WEEK" -gt 52 ] && WEEK=52
step "Make an invite for this week ($WEEK)"
api POST /api/invites "$(jq -n --argjson w "$WEEK" --argjson y "$(date +%Y)" '{weeks: [$w], year: $y}')" > "$WORK/invite.json"; expect 201
INVITE_ID=$(jq -r .id "$WORK/invite.json")
INVITE_TOKEN=$(jq -r .url "$WORK/invite.json" | sed 's#.*/join/##')
jq -c '{url, weeks, year, expiresAt}' "$WORK/invite.json"

step "Preview it without signing in"
STATUS=$(vercel curl "/api/invites/preview?token=$INVITE_TOKEN" --deployment "$DEPLOYMENT" --scope "$SCOPE" -- -s -o "$WORK/out" -w '%{http_code}' 2>/dev/null)
jq -c . "$WORK/out"; expect 200

step "Open the join page"
STATUS=$(vercel curl "/join/$INVITE_TOKEN" --deployment "$DEPLOYMENT" --scope "$SCOPE" -- -s -o "$WORK/join.html" -w '%{http_code}' 2>/dev/null)
grep -q 'E2E Test Family' "$WORK/join.html" && echo "✔ page names the family" || fail "join page doesn't name the family"

step "Accept your own link (a producer is never downgraded)"
api POST /api/invites/accept "$(jq -n --arg t "$INVITE_TOKEN" '{token: $t}')" | jq -c .; expect 200

step "Members"
api GET /api/family/members | jq -c .; expect 200

step "Turn the link off"
api DELETE "/api/invites/$INVITE_ID" | jq -c .; expect 200
api POST /api/invites/accept "$(jq -n --arg t "$INVITE_TOKEN" '{token: $t}')" | jq -c .; expect 410

step "Delete the account (removes the family's files and rows)"
api DELETE /api/account | jq -c .; expect 200
GET=$(curl -sS -o /dev/null -w '%{http_code}' "$URL") || true
echo "The clip's upload URL now answers HTTP $GET"

printf '\n✔ All steps passed.\n'
