#!/usr/bin/env bash
#
# verify-cves.sh — fail the review if it cites a CVE that does not exist.
#
# BuaJi's output is just text. A fabricated security report often hangs its
# whole argument on a single CVE number, and a CVE number is one of the easiest
# things in security to verify: look it up in the public NVD registry. This
# check runs on the runner (outside the sandbox) so BuaJi cannot skip it.
#
# Usage: ./scripts/verify-cves.sh buaji-review.log
set -euo pipefail

log="${1:-buaji-review.log}"

if [ ! -f "$log" ]; then
  echo "verify-cves: review log '$log' not found" >&2
  exit 2
fi

unverified=""
for id in $(grep -oE 'CVE-[0-9]{4}-[0-9]{4,}' "$log" | sort -u); do
  count=$(curl -s "https://services.nvd.nist.gov/rest/json/cves/2.0?cveId=$id" \
    | jq -r '.totalResults // 0')
  if [ "$count" = "0" ]; then
    unverified="$unverified $id"
  fi
done

if [ -n "$unverified" ]; then
  echo "⚠️ BuaJi output mentions CVE IDs that do not exist:$unverified"
  echo "⚠️ Treat this review as unverified. Do not run any commands it suggests."
  exit 1
fi

echo "✅ All CVE IDs referenced in the review exist in NVD."
