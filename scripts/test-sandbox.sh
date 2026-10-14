#!/usr/bin/env bash
#
# test-sandbox.sh — end-to-end self-test of the BuaJi Docker Sandbox setup,
# with no GPU and no multi-GB model download.
#
# It builds the sandbox template, runs BuaJi inside a microVM against a throwaway
# Go project (so there is always something to review), and asserts the guarantees
# the blog's Sandboxing section promises:
#   * the repo is mounted read-only (writes are refused by the kernel)
#   * there is no kubectl / terraform to misuse
#   * only the model's port is reachable; it is denied until explicitly allowed
#   * the review runs and the CVE gate accepts a clean report
#
# Everything is isolated: a dedicated sandbox name, a non-default mock port, and
# a temp project — so it never touches your real repo, git history, sandboxes,
# or a running Ollama on 11434. Cleans up after itself.
#
# Usage:  ./scripts/test-sandbox.sh [--rebuild]
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAME="buaji-selftest"
TEMPLATE="buaji-sandbox:selftest"
PORT="11888"                       # avoid a real Ollama on 11434
SCRATCH="/tmp/${NAME}-scratch"
TAR="/tmp/${NAME}.tar"
REVIEW="/tmp/${NAME}-review.log"
WORK=""
MOCK_PID=""
PASS=0; FAIL=0

say()  { printf '\n\033[1m== %s\033[0m\n' "$*"; }
ok()   { printf '  \033[32m✓ %s\033[0m\n' "$*"; PASS=$((PASS+1)); }
bad()  { printf '  \033[31m✗ %s\033[0m\n' "$*"; FAIL=$((FAIL+1)); }

cleanup() {
  say "Cleanup"
  if [ -n "$MOCK_PID" ]; then kill "$MOCK_PID" 2>/dev/null && echo "  mock stopped"; wait "$MOCK_PID" 2>/dev/null || true; fi
  sbx stop "$NAME"  >/dev/null 2>&1 || true
  sbx rm -f "$NAME" >/dev/null 2>&1 && echo "  sandbox removed" || true
  [ -n "$WORK" ] && rm -rf "$WORK"
  rm -f "$TAR" "$REVIEW"
  rm -rf "$SCRATCH"
}
trap cleanup EXIT

# --- template: build once, load into the sbx runtime ------------------------
say "Template"
if [ "${1:-}" = "--rebuild" ] || ! sbx template ls 2>/dev/null | grep -q "$NAME\|selftest"; then
  docker buildx build -f "$REPO/buaji.sandbox.Dockerfile" -t "$TEMPLATE" --load "$REPO" >/dev/null
  docker save "$TEMPLATE" -o "$TAR"
  sbx template load "$TAR" >/dev/null
  echo "  built + loaded $TEMPLATE"
else
  echo "  reusing already-loaded $TEMPLATE (pass --rebuild to force)"
fi

# --- mock model on the host --------------------------------------------------
say "Mock model"
python3 "$REPO/scripts/mock-ollama.py" "$PORT" & MOCK_PID=$!
# wait for it to accept connections (use 127.0.0.1 — on macOS `localhost` may
# resolve to IPv6 ::1, which the IPv4-bound mock does not answer)
for _ in $(seq 1 20); do
  code="$(curl -s -m2 -o /dev/null -w '%{http_code}' \
    "http://127.0.0.1:$PORT/api/generate" -X POST -d '{}' 2>/dev/null || true)"
  [ "$code" = "200" ] && break
  sleep 0.3
done
echo "  host mock on 127.0.0.1:$PORT -> ${code:-000}"
[ "${code:-000}" = "200" ] || { echo "  mock failed to start"; exit 1; }

# --- throwaway project with a reviewable Go diff -----------------------------
say "Throwaway project (so there is a HEAD^..HEAD Go diff)"
# pwd -P resolves macOS /var -> /private/var so the mount path matches inside
WORK="$(cd "$(mktemp -d)" && pwd -P)"
cp "$REPO/buaji.py" "$REPO/rules.md" "$WORK/"
(
  cd "$WORK"
  git init -q
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m "init"
  printf 'package main\n\nfunc main() {}\n' > sample.go
  git add -A
  git -c user.email=t@t -c user.name=t commit -q -m "add sample.go"
)
echo "  $WORK (sample.go committed)"

# --- create the sandbox: code read-only, scratch writable --------------------
say "Create sandbox (code mounted :ro)"
mkdir -p "$SCRATCH"
sbx rm -f "$NAME" >/dev/null 2>&1 || true
# NOTE: braces around ${WORK} are required — in zsh, "$WORK:ro" would trigger
# the :r history modifier and mangle the path.
sbx run -d --pull never --name "$NAME" -t "$TEMPLATE" \
  shell "$SCRATCH" "${WORK}:ro" >/dev/null
echo "  sandbox $NAME up"

# --- assertions --------------------------------------------------------------
say "Guarantees"

if ! sbx exec "$NAME" bash -c "test -d '${WORK}'" 2>/dev/null; then
  bad "repo mount not visible at ${WORK} inside the sandbox"
else
  touch_out="$(sbx exec "$NAME" bash -c "touch '${WORK}/HACKED' 2>&1" 2>&1 || true)"
  if sbx exec "$NAME" bash -c "test -e '${WORK}/HACKED'" 2>/dev/null; then
    bad "repo was NOT read-only (write succeeded)"
    sbx exec "$NAME" bash -c "rm -f '${WORK}/HACKED'" 2>/dev/null || true
  else
    ok "repo is read-only — write refused: ${touch_out:-non-zero exit}"
  fi
fi

if sbx exec "$NAME" bash -c 'command -v kubectl terraform >/dev/null 2>&1' ; then
  bad "kubectl/terraform present in sandbox"
else
  ok "no kubectl / terraform to misuse"
fi

# model path blocked until we allow it
code_before="$(sbx exec "$NAME" bash -c "curl -s -m6 -o /dev/null -w '%{http_code}' http://host.docker.internal:$PORT/api/generate -X POST -d '{}'" 2>/dev/null || true)"
if [ "$code_before" = "200" ]; then
  bad "model port reachable BEFORE allow (default policy is not deny-all)"
else
  ok "model port denied by default (got '$code_before')"
fi

sbx policy allow network --sandbox "$NAME" "localhost:$PORT" >/dev/null
code_after="$(sbx exec "$NAME" bash -c "curl -s -m6 -o /dev/null -w '%{http_code}' http://host.docker.internal:$PORT/api/generate -X POST -d '{}'" 2>/dev/null || true)"
if [ "$code_after" = "200" ]; then
  ok "model port reachable AFTER scoped allow"
else
  bad "model port still unreachable after allow (got '$code_after')"
fi

# --- run the review + CVE gate ----------------------------------------------
say "Run BuaJi in the sandbox"
sbx exec -w "$WORK" \
  -e LLM=gemma -e OLLAMA_URL="http://host.docker.internal:$PORT" \
  -e GIT_CONFIG_COUNT=1 -e GIT_CONFIG_KEY_0=safe.directory -e GIT_CONFIG_VALUE_0='*' \
  "$NAME" python3 buaji.py | tee "$REVIEW" | grep -E "📁|->" || true

if grep -q "sample.go" "$REVIEW" && grep -q "mock reviewer" "$REVIEW"; then
  ok "review ran and reached the (mock) model"
else
  bad "review did not produce expected output"
fi

say "CVE gate on the review"
if "$REPO/scripts/verify-cves.sh" "$REVIEW"; then
  ok "CVE gate passed (clean report)"
else
  bad "CVE gate failed on a clean report"
fi

say "What the sandbox tried to reach"
sbx policy log "$NAME" --limit 10 2>/dev/null || true

say "Result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
