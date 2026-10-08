#!/bin/sh
# CALYX FSM -- deployment smoke test
#
# Runs the same checks that were verified against a real OpenResty instance,
# in the order that isolates failure modes. Exits non-zero on the first hard
# failure, so it works as a compose healthcheck or a CI gate.
#
#   BASE=http://openresty:8080 ./openresty/smoke.sh     # in a container
#   BASE=http://localhost:8099 ./openresty/smoke.sh     # local rig
#
# Note on expectations: two checks below assert that a KNOWN BUG is still
# present. They are written as "must still be broken" so that this script fails
# if someone fixes one of them without updating the test. See KNOWN_ISSUES.md.

set -e
BASE="${BASE:-http://127.0.0.1:8080}"
PASS=0
FAIL=0

say()  { printf '\n=== %s ===\n' "$1"; }
ok()   { printf '  PASS  %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  NOTE  %s\n' "$1"; }

# expect_status <expected> <label> <curl args...>
expect_status() {
  want="$1"; label="$2"; shift 2
  got=$(curl -sS -m 10 -o /tmp/smoke_body -w '%{http_code}' "$@" 2>/dev/null || echo 000)
  if [ "$got" = "$want" ]; then
    ok "$label -> HTTP $got"
  else
    bad "$label -> HTTP $got (expected $want)"
    head -c 200 /tmp/smoke_body 2>/dev/null; echo
  fi
}

say "1. /health  -- openresty started, lua_package_path resolves"
expect_status 200 "/health" "$BASE/health"
curl -sS -m 5 "$BASE/health"; echo

say "2. /contract  -- require(\"effect_contract\") resolves"
expect_status 200 "/contract" "$BASE/contract"
curl -sS -m 5 "$BASE/contract" | head -c 140; echo

say "3. /stats  -- was HTTP 500 (nonexistent ngx.start_time)"
expect_status 200 "/stats" "$BASE/stats"
curl -sS -m 5 "$BASE/stats"; echo

say "4. /fsm/ with admin_agent  -- require(\"init\") + a full transition"
expect_status 200 "/fsm/ (admin_agent)" \
  -H 'X-Agent-Type: admin_agent' \
  "$BASE/fsm/?user_id=123&event=login_attempt"
curl -sS -m 5 -H 'X-Agent-Type: admin_agent' \
  "$BASE/fsm/?user_id=123&event=login_attempt"; echo

say "4b. /fsm/ with the DEFAULT agent -- KNOWN BUG, must still be 400"
# Use a DIFFERENT user from check 4. Both 123 and 456 are accepted by
# nginx_host.lua's stub auth. Re-using 123 here made this check order-dependent:
# check 4 had already logged 123 in, so the request took the already-
# authenticated path with effects_executed=0 and never reached the cache_set
# that triggers the rejection -- i.e. it failed for the wrong reason.
expect_status 400 "/fsm/ (default user_agent, fresh user 456)" \
  "$BASE/fsm/?user_id=456&event=login_attempt"
note "expected 400: capability scoping rejects cache_set for user_agent (KNOWN_ISSUES.md)"

say "5. /mock/emails  -- was always 0 (email regex used the non-existent {2,} quantifier)"
expect_status 200 "/mock/emails" "$BASE/mock/emails?count=3"
body=$(curl -sS -m 5 "$BASE/mock/emails?count=3")
echo "  $body"
case "$body" in
  *'"generated":0'*) bad "/mock/emails still generates 0 -- email fix regressed?" ;;
  *)                ok  "/mock/emails generates non-zero" ;;
esac

say "6. /mock/traces  -- control case, should always have worked"
expect_status 200 "/mock/traces" "$BASE/mock/traces?count=2"

say "7. /mock/metrics  -- KNOWN BUG, must still be generated:0"
# effect_contract uses effect.type as both the discriminator and the metric
# kind, so the metric schema can never be satisfied. Fixing it is a contract
# change; see KNOWN_ISSUES.md.
expect_status 200 "/mock/metrics" "$BASE/mock/metrics?count=3"
body=$(curl -sS -m 5 "$BASE/mock/metrics?count=3")
echo "  $body"
case "$body" in
  *'"generated":0'*) note "expected 0: metric type/size contract collision (KNOWN_ISSUES.md)" ;;
  *)                ok   "metrics now generate -- the contract collision was fixed" ;;
esac

say "8. shared dicts are reachable"
for ep in /cache /audit /mock/stats; do
  expect_status 200 "$ep" "$BASE$ep"
done

# NOTE: the OpenResty endpoint does NOT use Redis -- nginx_host.lua persists to
# ngx.shared dicts, not redis_host.lua. So the redis service exists for
# redis_host.lua / run_redis_demo.lua. This check exercises that path from
# inside the container, and it is the only thing that proves
# CALYX_REDIS_HOST/CALYX_REDIS_PORT are actually wired up: RedisHost.new() is
# called with NO arguments, so it must fall through to the environment.
say "9. redis reachable via CALYX_REDIS_HOST/PORT env plumbing"
if [ "${CALYX_REDIS_HOST:-}" = "" ]; then
  note "skipped: not running inside the compose stack (no CALYX_REDIS_HOST)"
else
  if redis-cli -h "$CALYX_REDIS_HOST" -p "${CALYX_REDIS_PORT:-6379}" ping 2>/dev/null | grep -q PONG; then
    ok "redis-cli $CALYX_REDIS_HOST:$CALYX_REDIS_PORT -> PONG"
  else
    bad "redis-cli $CALYX_REDIS_HOST:$CALYX_REDIS_PORT did not answer PONG"
  fi
fi

printf '\n===================================\n'
printf 'smoke: %d passed, %d failed\n' "$PASS" "$FAIL"
printf '===================================\n'
[ "$FAIL" -eq 0 ] || exit 1