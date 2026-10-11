#!/usr/bin/env bash
# End-to-end: a throwaway gaca-api + the fake Hermes, seeded with an account, crew, alerts,
# a briefing and an artifact; then the UI tests run against them in the simulator.
#
#   tools/e2e.sh                      # all UI flows
#   tools/e2e.sh FlowTests/testFailedRunShowsError   # one flow
#
# Needs ../gaca checked out next to this repo, and uv.
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
API_DIR="${GACA_API_DIR:-$HERE/../gaca/gaca-api}"
API_PORT="${API_PORT:-41799}"
HERMES_PORT="${HERMES_PORT:-18642}"
SIM="${SIM:-iPhone 17}"
BASE="http://127.0.0.1:$API_PORT/api"
WORK="$(mktemp -d)"
PIDS=()

cleanup() { for p in "${PIDS[@]:-}"; do kill "$p" 2>/dev/null || true; done; }
trap cleanup EXIT

wait_for() { for _ in $(seq 1 60); do curl -sf "$1" >/dev/null 2>&1 && return 0; sleep 0.5; done; echo "timed out waiting for $1" >&2; return 1; }

# Anything left over from an interrupted run would answer instead of our fresh servers.
lsof -ti ":$API_PORT" -ti ":$HERMES_PORT" | xargs kill 2>/dev/null || true
sleep 0.5

export GACA_DB_PATH="$WORK/gaca.db" GACA_AGENT_ENGINE=hermes GACA_API_PORT="$API_PORT" \
  GACA_JWT_SECRET="e2e-secret-that-is-long-enough-for-hs256-signing" GACA_PUBLIC_URL="http://127.0.0.1:$API_PORT"

echo "› starting gaca-api on :$API_PORT (db in $WORK)"
(cd "$API_DIR" && uv run uvicorn gaca_api.main:app --port "$API_PORT" --log-level warning >"$WORK/api.log" 2>&1) &
PIDS+=($!)
wait_for "$BASE/health"

post() { curl -sS --fail-with-body -X "${3:-POST}" "$BASE/$1" -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d "$2"; }
json() { python3 -c "import sys,json; print(json.load(sys.stdin)$1)"; }

echo "› seeding"
# A pairing code, the same way the owner gets one: `gaca-api pair` on the server.
pair_code() { (cd "$API_DIR" && uv run gaca-api pair --no-qr) 2>/dev/null | sed -n 's/^Pairing code:  *\([^ ]*\).*/\1/p'; }
CODE=$(pair_code)
TOKEN=$(curl -sS --fail-with-body -X POST "$BASE/devices/pair" -H 'Content-Type: application/json' \
  -d "{\"code\":\"$CODE\",\"name\":\"e2e seeder\"}" | json "['access_token']")

ARTIFACT=$(post artifacts '{"title":"Disk usage","description":"By directory, refreshed hourly","crew":"toolshed",
  "state":{"count":1},
  "html":"<h1>Disk usage</h1><p>E2E page body</p><p id=\"c\">loading</p><script>app.state.get().then(function(s){document.getElementById(\"c\").textContent=\"count: \"+(s.count||0)})</script>"}' | json "['id']")

echo "› starting fake Hermes on :$HERMES_PORT (artifact $ARTIFACT)"
(cd "$HERE" && FAKE_ARTIFACT_ID="$ARTIFACT" uv run --project "$API_DIR" python tools/fake_hermes.py --port "$HERMES_PORT" >"$WORK/hermes.log" 2>&1) &
PIDS+=($!)
wait_for "http://127.0.0.1:$HERMES_PORT/v1/skills"

post agent/connect "{\"host\":\"http://127.0.0.1\",\"port\":$HERMES_PORT,\"api_key\":\"fake\",\"name\":\"hermes\"}" >/dev/null
post crew "{\"name\":\"toolshed\",\"port\":$HERMES_PORT,\"api_key\":\"fake\",\"color\":\"#6B8F5A\"}" >/dev/null
post crew "{\"name\":\"trading\",\"port\":$HERMES_PORT,\"api_key\":\"fake\",\"color\":\"#B97A56\"}" >/dev/null

post alerts "{\"kind\":\"disk.low\",\"severity\":\"urgent\",\"title\":\"Disk usage on gaca-pi is at 92%\",
  \"body\":\"toolshed reported disk_low again — same volume as last week.\",\"crew\":\"toolshed\",\"source\":\"toolshed\",
  \"data\":{\"volume\":\"/dev/sda1\",\"used\":\"92%\",\"free_gb\":9.4},\"artifact_id\":\"$ARTIFACT\",
  \"suggested_actions\":[{\"label\":\"Prune old Docker images\",\"prompt\":\"Prune old Docker images on gaca-pi.\"}],
  \"links\":[{\"url\":\"https://example.com/dash\",\"label\":\"Dashboard\"}]}" >/dev/null
post alerts '{"kind":"backup","severity":"info","title":"Nightly backup finished","body":"42 GB written, 0 errors.","crew":"hermes","source":"hermes"}' >/dev/null
post alerts '{"kind":"trading","severity":"warn","title":"AAPL crossed your $230 alert","body":"Up 3.2% today on an earnings beat.","crew":"trading","source":"trading"}' >/dev/null

TODAY=$(date +%Y-%m-%d)
post "briefings/$TODAY" '{"summary":"A quiet Saturday. Lunch with Sam at noon, rain after six."}' PUT >/dev/null
post "briefings/$TODAY/sections/calendar" '{"title":"Calendar","kind":"calendar","headline":"2 events","items":[
  {"title":"Lunch with Sam","time":"12:00 PM","location":"Tartine","priority":"medium"},
  {"title":"Farmers market","time":"Before 2:00 PM","location":"Ferry Building","priority":"low"}]}' PUT >/dev/null

# A fresh code for the pairing-screen test (issuing one replaces any earlier code).
UI_CODE=$(pair_code)

echo "› running UI tests on $SIM"
ONLY="-only-testing:GacaUITests"
[[ $# -gt 0 ]] && ONLY="-only-testing:GacaUITests/$1"
cd "$HERE"
rm -rf build/e2e.xcresult
TEST_RUNNER_GACA_E2E_BASE="$BASE/" TEST_RUNNER_GACA_E2E_TOKEN="$TOKEN" \
TEST_RUNNER_GACA_E2E_SERVER="http://127.0.0.1:$API_PORT" TEST_RUNNER_GACA_E2E_CODE="$UI_CODE" \
xcodebuild -project Gaca.xcodeproj -scheme Gaca -destination "platform=iOS Simulator,name=$SIM" \
  -derivedDataPath build/dd -resultBundlePath build/e2e.xcresult -collect-test-diagnostics never $ONLY test CODE_SIGNING_ALLOWED=NO \
  | grep -E "Test Case|error:|failed|TEST (SUCCEEDED|FAILED)" || true
echo "› logs: $WORK  · results: build/e2e.xcresult"
